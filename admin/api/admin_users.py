import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete

from .db import get_db
from .models import AdminUser, InviteLink, RefreshToken
from .deps import require_role, write_audit, pwd_ctx

router = APIRouter(prefix="/api/admin-users", tags=["admin-users"])
_superadmin = require_role("superadmin")

VALID_ROLES = {"superadmin", "admin"}
INVITE_EXPIRE_HOURS = 24


class CreateUserRequest(BaseModel):
    username: str
    password: str
    role: str


class PatchUserRequest(BaseModel):
    role: str | None = None
    password: str | None = None
    is_active: bool | None = None


class InviteRequest(BaseModel):
    role: str


@router.get("")
async def list_users(db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    result = await db.execute(select(AdminUser))
    users = result.scalars().all()
    return {"users": [
        {"id": u.id, "username": u.username, "role": u.role, "is_active": u.is_active, "created_at": u.created_at}
        for u in users
    ]}


@router.post("", status_code=201)
async def create_user(body: CreateUserRequest, db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    if body.role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail=f"role must be one of {VALID_ROLES}")
    existing = await db.execute(select(AdminUser).where(AdminUser.username == body.username))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Username already exists")
    if len(body.password) < 12:
        raise HTTPException(status_code=400, detail="Password must be at least 12 characters")
    user = AdminUser(
        username=body.username,
        password_hash=pwd_ctx.hash(body.password),
        role=body.role,
        created_by=actor.username,
    )
    db.add(user)
    await db.commit()
    await write_audit(db, actor.id, "create_admin_user", body.username)
    return {"id": user.id, "username": user.username, "role": user.role}


@router.patch("/{user_id}")
async def patch_user(user_id: str, body: PatchUserRequest, db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    result = await db.execute(select(AdminUser).where(AdminUser.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if body.role and body.role != user.role and user.id == actor.id:
        raise HTTPException(status_code=400, detail="Cannot change your own role")
    if body.role:
        if body.role not in VALID_ROLES:
            raise HTTPException(status_code=400, detail=f"role must be one of {VALID_ROLES}")
        user.role = body.role
    if body.password:
        if len(body.password) < 12:
            raise HTTPException(status_code=400, detail="Password must be at least 12 characters")
        user.password_hash = pwd_ctx.hash(body.password)
    if body.is_active is not None:
        user.is_active = body.is_active
    await db.commit()
    await write_audit(db, actor.id, "patch_admin_user", user_id)
    return {"id": user.id, "username": user.username, "role": user.role}


@router.delete("/{user_id}")
async def deactivate_user(user_id: str, db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    result = await db.execute(select(AdminUser).where(AdminUser.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.id == actor.id:
        raise HTTPException(status_code=400, detail="Cannot delete yourself")
    await db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))
    await db.delete(user)
    await db.commit()
    await write_audit(db, actor.id, "delete_admin_user", user_id)
    return {"status": "deleted"}


@router.post("/invite", status_code=201)
async def create_invite(body: InviteRequest, db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    if body.role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail=f"role must be one of {VALID_ROLES}")
    raw_token = secrets.token_urlsafe(24)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    expires = datetime.now(timezone.utc) + timedelta(hours=INVITE_EXPIRE_HOURS)
    db.add(InviteLink(created_by=actor.username, token_hash=token_hash, role=body.role, expires_at=expires))
    await db.commit()
    await write_audit(db, actor.id, "create_invite", body.role)
    return {"invite_token": raw_token, "expires_at": expires, "role": body.role}
