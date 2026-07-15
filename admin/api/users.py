import os
import re
import secrets
from datetime import datetime

from cryptography import x509
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .deps import pwd_ctx, require_role, write_audit
from .docker_exec import run_in_container
from .models import AdminUser
from .password_policy import validate_password

router = APIRouter(prefix="/api/users", tags=["users"])
_admin = require_role("admin", "superadmin")

TAK_DATA = "/opt/tak/data/certs/files"
CLIENTPKGS = f"{TAK_DATA}/clientpkgs"
SERVER_ADDR = os.environ.get("TAK_SERVER_ADDRESS", "localhost")
TAK_USER_GROUP = os.environ.get("TAK_USER_GROUP", "TAK-USERS")

_USERNAME_RE = re.compile(r'^[A-Za-z0-9_-]+$')
_NEW_USERNAME_RE = re.compile(r'^[A-Za-z0-9_-]+-(ATAK|WinTAK|iTAK|Service)$')


def _validate_username(username: str) -> str:
    """For operations on an already-registered user (enable/disable/delete/etc).
    Looser check — older users created before the client-type suffix convention
    won't have one and must still be manageable."""
    if not _USERNAME_RE.fullmatch(username):
        raise HTTPException(status_code=400, detail="Username must be alphanumeric (hyphens/underscores allowed)")
    return username


def _validate_new_username(username: str) -> str:
    """For creating a new user — requires a client-type suffix so the package
    builder knows which zip layout to produce (iTAK's differs from ATAK/WinTAK)."""
    if not _NEW_USERNAME_RE.fullmatch(username):
        raise HTTPException(
            status_code=400,
            detail="Username must end in -ATAK, -WinTAK, -iTAK, or -Service (e.g. alpha1-iTAK)",
        )
    return username


def _cert_days_remaining(username: str) -> int | None:
    """Days until this user's own client cert expires, or None if the cert
    file is missing/unreadable — a package can exist without a readable
    cert in edge cases (e.g. mid-generation), so this degrades gracefully
    rather than failing the whole list."""
    path = os.path.join(TAK_DATA, f"{username}.pem")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "rb") as f:
            cert = x509.load_pem_x509_certificate(f.read())
        return (cert.not_valid_after - datetime.utcnow()).days
    except Exception:
        return None


def _base_callsign(username: str) -> str:
    for suffix in ("-ATAK", "-WinTAK", "-iTAK", "-Service"):
        if username.endswith(suffix):
            return username[: -len(suffix)]
    return username


async def _ensure_field_account(db: AsyncSession, base: str, created_by: str) -> tuple[bool, str | None]:
    """Create a field-role account for this base callsign if one doesn't
    already exist. Returns (created, password) — password is None when an
    existing account was reused (nothing new to show)."""
    existing = await db.execute(
        select(AdminUser).where(AdminUser.role == "field", AdminUser.owned_callsign == base)
    )
    if existing.scalar_one_or_none() is not None:
        return False, None
    password = secrets.token_urlsafe(12)
    db.add(AdminUser(
        username=base,
        password_hash=pwd_ctx.hash(password),
        role="field",
        owned_callsign=base,
        created_by=created_by,
    ))
    await db.commit()
    return True, password


class UsernameRequest(BaseModel):
    username: str


class SetPasswordRequest(BaseModel):
    username: str
    password: str


class RenameFieldAccountRequest(BaseModel):
    new_username: str


@router.get("")
async def list_users(db: AsyncSession = Depends(get_db), _=Depends(_admin)):
    code, out = await run_in_container(["bash", "-c", f"ls {CLIENTPKGS}/*.zip 2>/dev/null || true"])
    zips = [f.split("/")[-1].replace(".zip", "") for f in out.strip().splitlines() if f.endswith(".zip")]

    result = await db.execute(select(AdminUser.owned_callsign, AdminUser.username).where(AdminUser.role == "field"))
    field_logins = {row[0]: row[1] for row in result.all()}  # owned_callsign -> current (possibly renamed) username

    return {"users": [
        {
            "username": z,
            "has_field_account": _base_callsign(z) in field_logins,
            "field_username": field_logins.get(_base_callsign(z), _base_callsign(z)),
            "base_callsign": _base_callsign(z),
            "cert_days_remaining": _cert_days_remaining(z),
            "is_client": bool(_NEW_USERNAME_RE.fullmatch(z)),
        }
        for z in zips
    ]}


@router.post("/backfill-field-accounts", status_code=201)
async def backfill_field_accounts(db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    """Create a field account for every existing package that doesn't have one
    yet — covers packages made before field-account auto-creation existed."""
    code, out = await run_in_container(["bash", "-c", f"ls {CLIENTPKGS}/*.zip 2>/dev/null || true"])
    zips = [f.split("/")[-1].replace(".zip", "") for f in out.strip().splitlines() if f.endswith(".zip")]

    bases = sorted({_base_callsign(z) for z in zips})
    created_accounts = []
    for base in bases:
        created, password = await _ensure_field_account(db, base, actor.username)
        if created:
            await write_audit(db, actor.id, "create_field_account", base)
            created_accounts.append({"username": base, "password": password})

    return {"created": created_accounts}


@router.post("/gen-cert", status_code=201)
async def gen_cert(body: UsernameRequest, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_new_username(body.username)
    code, out = await run_in_container(
        ["bash", "/opt/scripts/gen_client_cert.sh"],
        env={"CLIENT_CERT_NAME": username},
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=out)
    await write_audit(db, actor.id, "gen_cert", username)
    return {"status": "ok", "output": out}


@router.post("/make-package", status_code=201)
async def make_package(body: UsernameRequest, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_new_username(body.username)
    code, out = await run_in_container(
        ["bash", "/opt/scripts/make_pkg_zip.sh"],
        env={"CLIENT_CERT_NAME": username, "TAK_SERVER_ADDRESS": SERVER_ADDR},
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=out)
    await write_audit(db, actor.id, "make_package", username)

    base = _base_callsign(username)
    created, password = await _ensure_field_account(db, base, actor.username)
    if created:
        await write_audit(db, actor.id, "create_field_account", base)

    return {
        "status": "ok",
        "package_name": username,
        "field_account_created": created,
        "field_account_password": password,
        "field_username": base,
    }


@router.post("/create-field-login/{username}", status_code=201)
async def create_field_login(username: str, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_username(username)
    if not os.path.isfile(os.path.join(CLIENTPKGS, f"{username}.zip")):
        raise HTTPException(status_code=404, detail="No package with that name exists")
    base = _base_callsign(username)
    created, password = await _ensure_field_account(db, base, actor.username)
    if created:
        await write_audit(db, actor.id, "create_field_account", base)
    return {"field_account_created": created, "field_account_password": password, "field_username": base}


@router.post("/field-account/{base}/rename")
async def rename_field_account(base: str, body: RenameFieldAccountRequest, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    """Renames a field account's login username only — owned_callsign (which
    actually links the account to its package/cert) is untouched, so the
    underlying package/cert keeps its original name. No cert regeneration."""
    new_username = _validate_username(body.new_username)

    result = await db.execute(
        select(AdminUser).where(AdminUser.role == "field", AdminUser.owned_callsign == base)
    )
    account = result.scalar_one_or_none()
    if account is None:
        raise HTTPException(status_code=404, detail="No field account for that package")

    existing = await db.execute(select(AdminUser).where(AdminUser.username == new_username))
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(status_code=409, detail="Username already taken")

    old_username = account.username
    account.username = new_username
    await db.commit()
    await write_audit(db, actor.id, "rename_field_account", f"{old_username} -> {new_username}")
    return {"username": new_username}


@router.post("/set-password")
async def set_tak_password(body: SetPasswordRequest, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_username(body.username)
    await validate_password(body.password)
    code, out = await run_in_container(
        ["java", "-jar", "utils/UserManager.jar", "usermod", "-u", username, "-p", body.password],
        workdir="/opt/tak",
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=out)
    await write_audit(db, actor.id, "set_tak_password", username)
    return {"status": "ok"}


@router.post("/enable")
async def enable_user(body: UsernameRequest, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_username(body.username)
    code, out = await run_in_container(
        ["bash", "/opt/scripts/enable_user.sh"],
        env={"USER_CERT_NAME": username, "TAK_USER_GROUP": TAK_USER_GROUP},
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=out)
    await write_audit(db, actor.id, "enable_user", username)
    return {"status": "ok"}


@router.post("/disable")
async def disable_user(body: UsernameRequest, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_username(body.username)
    code, out = await run_in_container(
        ["java", "-jar", "utils/UserManager.jar", "certmod",
         f"/opt/tak/data/certs/files/{username}.pem", "--disable"],
        workdir="/opt/tak",
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=out)
    await write_audit(db, actor.id, "disable_user", username)
    return {"status": "ok"}


@router.delete("/{username}")
async def delete_user(username: str, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_username(username)
    code, out = await run_in_container(
        ["bash", "/opt/scripts/delete_user.sh"],
        env={"USER_CERT_NAME": username},
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=out)
    await write_audit(db, actor.id, "delete_user", username)
    return {"status": "ok"}
