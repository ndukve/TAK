from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from api import oidc
from api.deps import get_current_user_active, pwd_ctx
from api.models import AdminUser


@pytest.fixture(autouse=True)
def _oidc_config(monkeypatch):
    monkeypatch.setattr(oidc, "OIDC_ISSUER", "https://idp.example.test")
    monkeypatch.setattr(oidc, "_ROLE_MAP", {"tak-admins": "admin"})


async def test_oidc_never_auto_links_a_local_username(db_session):
    db_session.add(AdminUser(
        username="alice",
        password_hash=pwd_ctx.hash("LocalPassword123!"),
        role="superadmin",
        created_by="test",
    ))
    await db_session.commit()

    with pytest.raises(HTTPException) as exc:
        await oidc._provision_user(db_session, {
            "sub": "external-alice",
            "preferred_username": "alice",
            "groups": ["tak-admins"],
        })
    assert exc.value.status_code == 409

    user = await db_session.scalar(select(AdminUser).where(AdminUser.username == "alice"))
    assert user.auth_provider == "local"
    assert user.oidc_subject is None
    assert user.role == "superadmin"


async def test_oidc_provisions_by_issuer_and_subject(db_session):
    user = await oidc._provision_user(db_session, {
        "sub": "stable-subject",
        "preferred_username": "person@example.test",
        "groups": ["tak-admins"],
    })
    assert user.username == "person_example.test"
    assert user.auth_provider == "oidc"
    assert user.oidc_issuer == "https://idp.example.test"
    assert user.oidc_subject == "stable-subject"
    assert user.role == "admin"


async def test_oidc_role_mapping_fails_closed_without_groups(db_session):
    with pytest.raises(HTTPException) as exc:
        await oidc._provision_user(db_session, {
            "sub": "missing-groups",
            "preferred_username": "alice",
        })
    assert exc.value.status_code == 403
    assert exc.value.detail == "OIDC groups claim missing"


async def test_oidc_cannot_downgrade_final_superadmin(db_session):
    user = AdminUser(
        username="only-superadmin",
        password_hash=pwd_ctx.hash("UnusableRandom123!"),
        role="superadmin",
        auth_provider="oidc",
        oidc_issuer="https://idp.example.test",
        oidc_subject="only-subject",
        created_by="test",
    )
    db_session.add(user)
    await db_session.commit()

    with pytest.raises(HTTPException) as exc:
        await oidc._provision_user(db_session, {
            "sub": "only-subject",
            "preferred_username": "only-superadmin",
            "groups": ["tak-admins"],
        })
    assert exc.value.status_code == 409
    assert exc.value.detail == "Cannot remove the final active superadmin"


async def test_oidc_accounts_do_not_enter_local_password_expiry(db_session):
    user = AdminUser(
        username="sso-user",
        password_hash=pwd_ctx.hash("UnusableRandom123!"),
        role="admin",
        auth_provider="oidc",
        oidc_issuer="https://idp.example.test",
        oidc_subject="sso-subject",
        password_changed_at=datetime.now(UTC) - timedelta(days=365),
        created_by="test",
    )
    assert await get_current_user_active(user) is user
