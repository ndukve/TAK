import os
from datetime import UTC, datetime, timedelta

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .models import AdminUser, AuditLog

SECRET_KEY = os.environ.get("ADMIN_SECRET_KEY", "")
if len(SECRET_KEY.encode()) < 32:
    raise RuntimeError("ADMIN_SECRET_KEY is required and must be at least 32 bytes")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 15
PASSWORD_ROTATION_DAYS = 90


class BcryptContext:
    """Small compatibility wrapper around bcrypt's standard $2b$ hashes.

    This intentionally retains the ``hash``/``verify`` interface used by the
    application and tests, without Passlib's obsolete bcrypt-version probe.
    Existing password hashes remain fully compatible.
    """

    @staticmethod
    def hash(password: str) -> str:
        return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("ascii")

    @staticmethod
    def verify(password: str, password_hash: str) -> bool:
        try:
            return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("ascii"))
        except (TypeError, ValueError, UnicodeError):
            return False


pwd_ctx = BcryptContext()
bearer = HTTPBearer(auto_error=False)


def create_access_token(data: dict, expires_delta: timedelta = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(UTC) + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode["exp"] = expire
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
    db: AsyncSession = Depends(get_db),
) -> AdminUser:
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")
    except jwt.InvalidTokenError as err:
        raise HTTPException(status_code=401, detail="Invalid token") from err

    result = await db.execute(select(AdminUser).where(AdminUser.id == user_id, AdminUser.is_active))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="User not found or inactive")
    return user


async def get_current_user_active(user: AdminUser = Depends(get_current_user)) -> AdminUser:
    """Same as get_current_user, but also enforces password rotation. The
    change-password endpoint itself must depend on get_current_user directly
    (not this) — otherwise an expired-password user could never reach the
    one endpoint that lets them fix it."""
    if user.auth_provider == "oidc":
        return user
    age = datetime.now(UTC) - user.password_changed_at.replace(tzinfo=UTC)
    if age > timedelta(days=PASSWORD_ROTATION_DAYS):
        raise HTTPException(status_code=403, detail="password_expired")
    return user


def require_role(*roles: str):
    async def _check(user: AdminUser = Depends(get_current_user_active)) -> AdminUser:
        if user.role not in roles:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return user
    return _check


async def write_audit(db: AsyncSession, user_id: str | None, action: str, detail: str | None = None):
    db.add(AuditLog(user_id=user_id, action=action, detail=detail))
    await db.commit()
