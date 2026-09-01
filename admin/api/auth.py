import hashlib
import os
import secrets
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Cookie, Depends, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from .db import SessionLocal, get_db
from .deps import bearer, create_access_token, get_current_user, pwd_ctx, write_audit
from .models import AdminUser, RefreshToken
from .schemas import LoginRequest, ShellElevateRequest, ShellTicketResponse, TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])

REFRESH_TOKEN_EXPIRE_DAYS = 7
LOCKOUT_ATTEMPTS = 5
LOCKOUT_MINUTES = 15
SHELL_TICKET_EXPIRE_MINUTES = 5
WS_TICKET_EXPIRE_SECONDS = 30

# In-memory shell tickets {ticket_hash: (user_id, expires_at)} — acceptable for single-instance
_shell_tickets: dict[str, tuple[str, datetime]] = {}

# In-memory WS tickets {ticket_hash: (user_id, role, expires_at)} — short-lived,
# single-use stand-in for the real JWT on WebSocket routes, which can't send an
# Authorization header. Minted from an already-authenticated request (bearer
# JWT in the header, never in a URL) so the long-lived access token itself
# never has to travel in a query string that proxies/CDNs tend to log.
_ws_tickets: dict[str, tuple[str, str, datetime]] = {}

# Verified on every login attempt when no matching user exists, so a bcrypt
# compare always runs — otherwise a nonexistent username short-circuits
# before the slow hash check, and the timing gap lets an attacker enumerate
# valid usernames.
_DUMMY_PASSWORD_HASH = pwd_ctx.hash("no-such-user-timing-parity")


def _token_claims(user: AdminUser) -> dict[str, str]:
    return {
        "sub": user.id,
        "role": user.role,
        "username": user.username,
        "auth_provider": user.auth_provider,
    }


def _purge_expired_tickets() -> None:
    """Bound the in-memory ticket stores when tickets are minted but unused."""
    now = datetime.now(UTC)
    for store in (_shell_tickets, _ws_tickets):
        expired = [key for key, entry in store.items() if entry[-1] <= now]
        for key in expired:
            store.pop(key, None)


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, response: Response, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(AdminUser).where(AdminUser.username == body.username, AdminUser.is_active))
    user = result.scalar_one_or_none()

    now = datetime.now(UTC)

    if user and user.locked_until and user.locked_until.replace(tzinfo=UTC) > now:
        raise HTTPException(status_code=429, detail="Account temporarily locked")

    password_hash = user.password_hash if user else _DUMMY_PASSWORD_HASH
    password_ok = pwd_ctx.verify(body.password, password_hash)
    if not user or not password_ok:
        if user:
            user.failed_logins += 1
            if user.failed_logins >= LOCKOUT_ATTEMPTS:
                user.locked_until = now + timedelta(minutes=LOCKOUT_MINUTES)
                user.failed_logins = 0
            await db.commit()
        raise HTTPException(status_code=401, detail="Invalid credentials")

    user.failed_logins = 0
    user.locked_until = None
    await db.commit()

    access_token = create_access_token(_token_claims(user))

    raw_refresh = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_refresh.encode()).hexdigest()
    expires = datetime.now(UTC) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    db.add(RefreshToken(user_id=user.id, token_hash=token_hash, expires_at=expires))
    await db.commit()

    response.set_cookie("refresh_token", raw_refresh, httponly=True, secure=True, samesite="lax", max_age=60 * 60 * 24 * REFRESH_TOKEN_EXPIRE_DAYS)
    await write_audit(db, user.id, "login")
    return TokenResponse(access_token=access_token)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(response: Response, refresh_token: str = Cookie(None), db: AsyncSession = Depends(get_db)):
    if not refresh_token:
        raise HTTPException(status_code=401, detail="No refresh token")
    token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()
    now = datetime.now(UTC)
    result = await db.execute(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
    token = result.scalar_one_or_none()
    if not token or token.expires_at.replace(tzinfo=UTC) <= now:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    if token.revoked:
        # Reuse of an already-rotated-away token — signal the token family was
        # stolen. Revoke every refresh token for this user to force a fresh
        # login everywhere, rather than trusting this presented token.
        await db.execute(update(RefreshToken).where(RefreshToken.user_id == token.user_id).values(revoked=True))
        await db.commit()
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    user_result = await db.execute(select(AdminUser).where(AdminUser.id == token.user_id, AdminUser.is_active))
    user = user_result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="User inactive")

    # Atomically claim this refresh token. Without the conditional UPDATE,
    # two concurrent requests can both observe revoked=False and each mint a
    # successor, defeating rotation/replay detection.
    claimed = await db.scalar(
        update(RefreshToken)
        .where(RefreshToken.id == token.id, RefreshToken.revoked.is_(False))
        .values(revoked=True)
        .returning(RefreshToken.user_id)
        .execution_options(synchronize_session=False)
    )
    if claimed is None:
        await db.execute(update(RefreshToken).where(RefreshToken.user_id == token.user_id).values(revoked=True))
        await db.commit()
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    # Rotate: issue a new token in place of the one atomically claimed above.
    raw_refresh = secrets.token_urlsafe(32)
    new_hash = hashlib.sha256(raw_refresh.encode()).hexdigest()
    expires = now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    db.add(RefreshToken(user_id=user.id, token_hash=new_hash, expires_at=expires))
    await db.commit()

    response.set_cookie("refresh_token", raw_refresh, httponly=True, secure=True, samesite="lax", max_age=60 * 60 * 24 * REFRESH_TOKEN_EXPIRE_DAYS)

    access_token = create_access_token(_token_claims(user))
    return TokenResponse(access_token=access_token)


@router.post("/logout")
async def logout(response: Response, refresh_token: str = Cookie(None), db: AsyncSession = Depends(get_db)):
    if refresh_token:
        token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()
        result = await db.execute(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
        token = result.scalar_one_or_none()
        if token:
            token.revoked = True
            await db.commit()
    response.delete_cookie("refresh_token")
    return {"status": "logged out"}


@router.post("/shell-elevate", response_model=ShellTicketResponse)
async def shell_elevate(
    body: ShellElevateRequest,
    db: AsyncSession = Depends(get_db),
    user: AdminUser = Depends(get_current_user),
):
    if user.role != "superadmin":
        raise HTTPException(status_code=403, detail="Superadmin only")
    if user.auth_provider != "local":
        raise HTTPException(status_code=403, detail="Shell requires a local break-glass account")
    if not pwd_ctx.verify(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid password")

    _purge_expired_tickets()
    ticket = secrets.token_urlsafe(32)
    ticket_hash = hashlib.sha256(ticket.encode()).hexdigest()
    expires = datetime.now(UTC) + timedelta(minutes=SHELL_TICKET_EXPIRE_MINUTES)
    _shell_tickets[ticket_hash] = (user.id, expires)
    await write_audit(db, user.id, "shell_elevate")
    return ShellTicketResponse(ticket=ticket, expires_at=expires)


def consume_shell_ticket(ticket: str) -> str | None:
    """Returns user_id if ticket is valid and not expired. Consumes it (single-use)."""
    ticket_hash = hashlib.sha256(ticket.encode()).hexdigest()
    entry = _shell_tickets.pop(ticket_hash, None)
    if not entry:
        return None
    user_id, expires = entry
    if datetime.now(UTC) > expires:
        return None
    return user_id


@router.post("/ws-ticket")
async def issue_ws_ticket(user: AdminUser = Depends(get_current_user)):
    # No role gate here — the ticket just carries the caller's own role
    # forward; each consumer (WS routes, download routes) enforces its own
    # required roles when the ticket is redeemed via consume_ws_ticket.
    _purge_expired_tickets()
    ticket = secrets.token_urlsafe(32)
    ticket_hash = hashlib.sha256(ticket.encode()).hexdigest()
    expires = datetime.now(UTC) + timedelta(seconds=WS_TICKET_EXPIRE_SECONDS)
    _ws_tickets[ticket_hash] = (user.id, user.role, expires)
    return {"ticket": ticket}


def consume_ws_ticket(ticket: str) -> str | None:
    """Returns role if ticket is valid and not expired. Consumes it (single-use)."""
    ticket_hash = hashlib.sha256(ticket.encode()).hexdigest()
    entry = _ws_tickets.pop(ticket_hash, None)
    if not entry:
        return None
    _user_id, role, expires = entry
    if datetime.now(UTC) > expires:
        return None
    return role


def require_role_or_ticket(*roles: str):
    """Like deps.require_role, but also accepts a one-time ws-ticket in the
    query string. File downloads triggered via a plain <a href> (so the
    browser streams the response itself instead of buffering the whole file
    into a JS Blob) can't carry an Authorization header, hence the ticket."""
    async def _check(
        ticket: str | None = None,
        credentials: HTTPAuthorizationCredentials = Depends(bearer),
        db: AsyncSession = Depends(get_db),
    ) -> None:
        if ticket is not None:
            role = consume_ws_ticket(ticket)
            if role not in roles:
                raise HTTPException(status_code=401, detail="Invalid or expired ticket")
            return
        user = await get_current_user(credentials, db)
        if user.role not in roles:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
    return _check


async def _ensure_first_user():
    first_user = os.environ.get("ADMIN_FIRST_USER", "admin")
    first_pass = os.environ.get("ADMIN_FIRST_PASS", "")
    if not first_pass:
        return

    async with SessionLocal() as db:
        result = await db.execute(select(AdminUser).where(AdminUser.username == first_user))
        if result.scalar_one_or_none() is None:
            user = AdminUser(
                username=first_user,
                password_hash=pwd_ctx.hash(first_pass),
                role="superadmin",
                created_by="install",
            )
            db.add(user)
            await db.commit()
            print(f"[admin] First superadmin created: {first_user}", flush=True)
