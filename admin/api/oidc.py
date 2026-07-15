"""Optional OIDC / OAuth2 single sign-on (Keycloak, Authentik, any compliant
provider). Entirely gated behind environment configuration: with no issuer /
client credentials set, OIDC_ENABLED is False, the routes short-circuit, and
the app behaves exactly as before. This is infrastructure to connect an IdP
later — nothing runs unless it's configured.

Flow: /auth/oidc/login redirects to the IdP → IdP redirects back to
/auth/oidc/callback → we exchange the code, map the user's IdP groups to a
panel role, JIT-provision (or link) an AdminUser, then set the same httponly
refresh cookie a password login would and redirect to the SPA. On load the
SPA trades that cookie for an access token via /auth/refresh, so no token ever
travels in a URL."""

import hashlib
import os
import re
import secrets
from datetime import UTC, datetime, timedelta

from authlib.integrations.starlette_client import OAuth, OAuthError
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .deps import pwd_ctx, write_audit
from .models import AdminUser, RefreshToken

router = APIRouter(prefix="/auth/oidc", tags=["auth"])

# --- Configuration (env-driven) ---------------------------------------------
OIDC_ISSUER = os.environ.get("OIDC_ISSUER", "").rstrip("/")
OIDC_CLIENT_ID = os.environ.get("OIDC_CLIENT_ID", "")
OIDC_CLIENT_SECRET = os.environ.get("OIDC_CLIENT_SECRET", "")
OIDC_PROVIDER_NAME = os.environ.get("OIDC_PROVIDER_NAME", "SSO")
OIDC_SCOPES = os.environ.get("OIDC_SCOPES", "openid profile email groups")
OIDC_GROUPS_CLAIM = os.environ.get("OIDC_GROUPS_CLAIM", "groups")
# Explicit redirect URL registered with the IdP. Behind a reverse proxy the
# request URL the app sees is often the internal http one, so this override is
# usually required in prod (e.g. https://tak.example.com/auth/oidc/callback).
OIDC_REDIRECT_URL = os.environ.get("OIDC_REDIRECT_URL", "")
# Panel role granted when no group maps. Kept deliberately low.
OIDC_DEFAULT_ROLE = os.environ.get("OIDC_DEFAULT_ROLE", "readonly")
# "idp-group=panel-role" pairs, comma-separated.
# e.g. OIDC_ROLE_MAP="tak-superadmins=superadmin,tak-ops=admin,tak-ro=readonly"
OIDC_ROLE_MAP_RAW = os.environ.get("OIDC_ROLE_MAP", "")
# Where to send the browser after a successful callback — the SPA root, which
# trades the refresh cookie for an access token on load.
OIDC_POST_LOGIN_URL = os.environ.get("OIDC_POST_LOGIN_URL", "/")

OIDC_ENABLED = bool(OIDC_ISSUER and OIDC_CLIENT_ID and OIDC_CLIENT_SECRET)

if OIDC_ENABLED and not OIDC_ISSUER.startswith("https://"):
    raise RuntimeError("OIDC_ISSUER must use HTTPS")
if OIDC_ENABLED and (not OIDC_POST_LOGIN_URL.startswith("/") or OIDC_POST_LOGIN_URL.startswith("//")):
    raise RuntimeError("OIDC_POST_LOGIN_URL must be a same-origin absolute path")

REFRESH_TOKEN_EXPIRE_DAYS = 7
_VALID_ROLES = {"superadmin", "admin", "readonly", "field"}
# Higher wins when a user is in multiple mapped groups.
_ROLE_PRIORITY = {"superadmin": 3, "admin": 2, "readonly": 1, "field": 0}


def _parse_role_map(raw: str) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for pair in raw.split(","):
        pair = pair.strip()
        if not pair or "=" not in pair:
            continue
        group, role = (p.strip() for p in pair.split("=", 1))
        if group and role in _VALID_ROLES:
            mapping[group] = role
    return mapping


_ROLE_MAP = _parse_role_map(OIDC_ROLE_MAP_RAW)

# Registered lazily only when enabled, so an unconfigured deployment never
# touches authlib or the IdP discovery URL.
oauth = OAuth()
if OIDC_ENABLED:
    oauth.register(
        name="idp",
        client_id=OIDC_CLIENT_ID,
        client_secret=OIDC_CLIENT_SECRET,
        server_metadata_url=f"{OIDC_ISSUER}/.well-known/openid-configuration",
        client_kwargs={"scope": OIDC_SCOPES},
    )


def _role_for_groups(groups: list[str]) -> str:
    """Highest-priority role among the user's mapped groups, else the default."""
    roles = [_ROLE_MAP[g] for g in groups if g in _ROLE_MAP]
    if not roles:
        return OIDC_DEFAULT_ROLE if OIDC_DEFAULT_ROLE in _VALID_ROLES else "readonly"
    return max(roles, key=lambda r: _ROLE_PRIORITY.get(r, 0))


async def _provision_user(db: AsyncSession, claims: dict) -> AdminUser:
    """Find or create a user by immutable issuer/subject identity."""
    subject = str(claims.get("sub") or "").strip()
    if not subject:
        raise HTTPException(status_code=400, detail="OIDC token missing 'sub'")
    if len(subject) > 255:
        raise HTTPException(status_code=400, detail="OIDC subject is too long")

    raw_username = str(claims.get("preferred_username") or claims.get("email") or subject)
    username = re.sub(r"[^a-zA-Z0-9_.-]", "_", raw_username).strip("._-")[:64]
    if not username:
        username = f"oidc-{hashlib.sha256(subject.encode()).hexdigest()[:12]}"

    if _ROLE_MAP and OIDC_GROUPS_CLAIM not in claims:
        # A missing authoritative groups claim must not silently retain or
        # grant a privileged role after an IdP/userinfo configuration error.
        raise HTTPException(status_code=403, detail="OIDC groups claim missing")
    groups = claims.get(OIDC_GROUPS_CLAIM) or []
    if not isinstance(groups, list):
        groups = [groups]
    role = _role_for_groups([str(g) for g in groups])

    result = await db.execute(select(AdminUser).where(
        AdminUser.oidc_issuer == OIDC_ISSUER,
        AdminUser.oidc_subject == subject,
    ))
    user = result.scalar_one_or_none()

    if user:
        if not user.is_active:
            raise HTTPException(status_code=403, detail="Account disabled")
        if user.auth_provider != "oidc":
            raise HTTPException(status_code=409, detail="OIDC identity conflicts with a local account")
        if user.role == "superadmin" and role != "superadmin":
            count = await db.scalar(select(func.count()).select_from(AdminUser).where(
                AdminUser.role == "superadmin", AdminUser.is_active,
            ))
            if (count or 0) <= 1:
                raise HTTPException(status_code=409, detail="Cannot remove the final active superadmin")
        user.role = role
    else:
        collision = await db.scalar(select(AdminUser).where(AdminUser.username == username))
        if collision:
            raise HTTPException(
                status_code=409,
                detail="OIDC username already exists; choose a distinct IdP username",
            )
        user = AdminUser(
            username=username,
            # Unusable random hash — SSO accounts can never password-login.
            password_hash=pwd_ctx.hash(secrets.token_urlsafe(32)),
            role=role,
            auth_provider="oidc",
            oidc_issuer=OIDC_ISSUER,
            oidc_subject=subject,
            created_by="oidc",
        )
        db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.get("/config")
async def oidc_config():
    """Public — lets the login page decide whether to show the SSO button."""
    return {"enabled": OIDC_ENABLED, "provider_name": OIDC_PROVIDER_NAME}


@router.get("/login")
async def oidc_login(request: Request):
    if not OIDC_ENABLED:
        raise HTTPException(status_code=404, detail="OIDC not configured")
    redirect_uri = OIDC_REDIRECT_URL or str(request.url_for("oidc_callback"))
    return await oauth.idp.authorize_redirect(request, redirect_uri)


@router.get("/callback", name="oidc_callback")
async def oidc_callback(request: Request, db: AsyncSession = Depends(get_db)):
    if not OIDC_ENABLED:
        raise HTTPException(status_code=404, detail="OIDC not configured")
    try:
        token = await oauth.idp.authorize_access_token(request)
    except OAuthError:
        # State/nonce mismatch, user-denied consent, etc. — bounce to login.
        return RedirectResponse(url="/login?error=oidc", status_code=303)

    # userinfo enriches (and, for some IdPs, is the only source of) the groups
    # claim beyond what the id_token carries.
    claims = dict(token.get("userinfo") or {})
    try:
        info = await oauth.idp.userinfo(token=token)
        claims.update({k: v for k, v in dict(info).items() if v is not None})
    except Exception:
        pass  # id_token claims alone are sufficient if userinfo is unavailable.

    try:
        user = await _provision_user(db, claims)
    except HTTPException as exc:
        await db.rollback()
        await write_audit(db, None, "login_oidc_rejected", str(exc.detail)[:255])
        return RedirectResponse(url="/login?error=oidc_account", status_code=303)

    # Mint the same refresh session a password login would (mirrors auth.login).
    raw_refresh = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_refresh.encode()).hexdigest()
    expires = datetime.now(UTC) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    db.add(RefreshToken(user_id=user.id, token_hash=token_hash, expires_at=expires))
    await db.commit()
    await write_audit(db, user.id, "login_oidc")

    response = RedirectResponse(url=OIDC_POST_LOGIN_URL, status_code=303)
    response.set_cookie(
        "refresh_token", raw_refresh, httponly=True, secure=True, samesite="lax",
        max_age=60 * 60 * 24 * REFRESH_TOKEN_EXPIRE_DAYS,
    )
    return response
