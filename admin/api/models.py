import uuid
from datetime import UTC, datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def _uuid():
    return str(uuid.uuid4())


class AdminUser(Base):
    __tablename__ = "admin_users"
    __table_args__ = (
        Index("ix_admin_users_oidc_identity", "oidc_issuer", "oidc_subject", unique=True),
    )

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    username: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False)  # superadmin|admin|readonly
    # "local" for password accounts, "oidc" for SSO-provisioned ones. The
    # issuer/subject pair is the immutable external identity; usernames are
    # display/login names and must never be used to auto-link an SSO account.
    auth_provider: Mapped[str] = mapped_column(String(16), nullable=False, default="local")
    oidc_issuer: Mapped[str | None] = mapped_column(String(255), nullable=True)
    oidc_subject: Mapped[str | None] = mapped_column(String(255), nullable=True)
    owned_callsign: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_by: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(UTC))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    failed_logins: Mapped[int] = mapped_column(default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    password_changed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(UTC))

    tokens: Mapped[list["RefreshToken"]] = relationship(back_populates="user")


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("admin_users.id"), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(128), unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)

    user: Mapped["AdminUser"] = relationship(back_populates="tokens")


class AuditLog(Base):
    __tablename__ = "audit_log"

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    user_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    action: Mapped[str] = mapped_column(String(128), nullable=False)
    detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(UTC))


class BrandSettings(Base):
    __tablename__ = "brand_settings"

    id: Mapped[str] = mapped_column(String(16), primary_key=True, default=lambda: "singleton")
    org_name: Mapped[str] = mapped_column(String(64), default="TAK Admin")
    accent_fill: Mapped[str] = mapped_column(String(16), default="#2dd4bf")
    accent_fill_hover: Mapped[str] = mapped_column(String(16), default="#5eead4")
    accent_text: Mapped[str] = mapped_column(String(16), default="#052e2b")
    accent_ring: Mapped[str] = mapped_column(String(16), default="#2dd4bf")
    logo_filename: Mapped[str | None] = mapped_column(String(128), nullable=True)


class ReplayChunk(Base):
    __tablename__ = "replay_chunks"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=_uuid)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(UTC))
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    event_count: Mapped[int] = mapped_column(default=0)
    size_bytes: Mapped[int] = mapped_column(default=0)


class ReplaySettings(Base):
    __tablename__ = "replay_settings"

    id: Mapped[str] = mapped_column(String(16), primary_key=True, default=lambda: "singleton")
    max_disk_mb: Mapped[int] = mapped_column(default=0)
    min_free_disk_mb: Mapped[int] = mapped_column(default=1024)
    chunk_minutes: Mapped[int] = mapped_column(default=15)
    service_cert_ready: Mapped[bool] = mapped_column(Boolean, default=False)
