from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .deps import get_current_user, pwd_ctx, require_role, write_audit
from .models import AdminUser, RefreshToken
from .password_policy import validate_password

router = APIRouter(prefix="/api/admin-users", tags=["admin-users"])
_superadmin = require_role("superadmin")

VALID_ROLES = {"superadmin", "admin"}


class CreateUserRequest(BaseModel):
    username: str
    password: str
    role: str


class PatchUserRequest(BaseModel):
    role: str | None = None
    password: str | None = None
    is_active: bool | None = None


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


@router.get("")
async def list_users(db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    query = select(AdminUser).where(AdminUser.role != "field")
    result = await db.execute(query)
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
    await validate_password(body.password)
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
        await validate_password(body.password)
        user.password_hash = pwd_ctx.hash(body.password)
        user.password_changed_at = datetime.now(UTC)
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


@router.post("/me/change-password")
async def change_own_password(
    body: ChangePasswordRequest,
    db: AsyncSession = Depends(get_db),
    actor: AdminUser = Depends(get_current_user),
):
    # Deliberately get_current_user, not require_role/get_current_user_active —
    # this must stay reachable for every role (including field) and even once
    # the caller's password has expired, since it's the only way out of that state.
    if not pwd_ctx.verify(body.current_password, actor.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    await validate_password(body.new_password)
    actor.password_hash = pwd_ctx.hash(body.new_password)
    actor.password_changed_at = datetime.now(UTC)
    await db.commit()
    await write_audit(db, actor.id, "change_own_password", actor.username)
    return {"status": "ok"}
