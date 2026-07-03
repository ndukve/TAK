import os
import re
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .deps import require_role, write_audit
from .docker_exec import run_in_container
from .password_policy import validate_password

router = APIRouter(prefix="/api/users", tags=["users"])
_admin = require_role("admin", "superadmin")

TAK_DATA = "/opt/tak/data/certs/files"
CLIENTPKGS = f"{TAK_DATA}/clientpkgs"
SERVER_ADDR = os.environ.get("TAK_SERVER_ADDRESS", "localhost")

_USERNAME_RE = re.compile(r'^[A-Za-z0-9_-]+$')
_NEW_USERNAME_RE = re.compile(r'^[A-Za-z0-9_-]+-(ATAK|WinTAK|iTAK)$')


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
            detail="Username must end in -ATAK, -WinTAK, or -iTAK (e.g. alpha1-iTAK)",
        )
    return username


class UsernameRequest(BaseModel):
    username: str


class SetPasswordRequest(BaseModel):
    username: str
    password: str


@router.get("")
async def list_users(_=Depends(_admin)):
    code, out = await run_in_container(["bash", "-c", f"ls {CLIENTPKGS}/*.zip 2>/dev/null || true"])
    zips = [f.split("/")[-1].replace(".zip", "") for f in out.strip().splitlines() if f.endswith(".zip")]
    return {"users": zips}


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
    return {"status": "ok", "download_url": f"http://{SERVER_ADDR}:8888/{username}.zip"}


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
        env={"USER_CERT_NAME": username},
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
