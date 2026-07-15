from datetime import UTC, datetime, timedelta

import jwt
from sqlalchemy import select

from api.models import AdminUser, RefreshToken

from .conftest import ADMIN_PASSWORD


async def test_login_success_returns_access_token_and_refresh_cookie(client, admin_user):
    resp = await client.post("/auth/login", json={"username": admin_user.username, "password": ADMIN_PASSWORD})
    assert resp.status_code == 200
    body = resp.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"]
    assert "refresh_token" in resp.cookies
    claims = jwt.decode(body["access_token"], options={"verify_signature": False})
    assert claims["auth_provider"] == "local"


async def test_login_invalid_password_is_rejected(client, admin_user):
    resp = await client.post("/auth/login", json={"username": admin_user.username, "password": "wrong-password"})
    assert resp.status_code == 401
    assert resp.json()["detail"] == "Invalid credentials"


async def test_login_unknown_username_is_rejected(client):
    resp = await client.post("/auth/login", json={"username": "nobody", "password": "whatever"})
    assert resp.status_code == 401
    assert resp.json()["detail"] == "Invalid credentials"


async def test_login_unknown_username_still_runs_password_hash_compare(client, monkeypatch):
    # A nonexistent username must not short-circuit past the bcrypt compare —
    # skipping it makes login measurably faster for bad usernames than bad
    # passwords, letting an attacker enumerate valid accounts by timing.
    from api import auth as auth_module

    calls = []
    real_verify = auth_module.pwd_ctx.verify

    def spy_verify(secret, hash_):
        calls.append(hash_)
        return real_verify(secret, hash_)

    monkeypatch.setattr(auth_module.pwd_ctx, "verify", spy_verify)

    resp = await client.post("/auth/login", json={"username": "nobody", "password": "whatever"})
    assert resp.status_code == 401
    assert calls == [auth_module._DUMMY_PASSWORD_HASH]


async def test_login_inactive_user_is_rejected(client, session_factory, admin_user):
    async with session_factory() as session:
        user = await session.get(AdminUser, admin_user.id)
        user.is_active = False
        await session.commit()

    resp = await client.post("/auth/login", json={"username": admin_user.username, "password": ADMIN_PASSWORD})
    assert resp.status_code == 401
    assert resp.json()["detail"] == "Invalid credentials"


async def test_account_locks_after_five_failed_attempts(client, admin_user):
    for _ in range(5):
        resp = await client.post("/auth/login", json={"username": admin_user.username, "password": "wrong"})
        assert resp.status_code == 401

    # 6th attempt — even with the *correct* password — must be locked out.
    resp = await client.post("/auth/login", json={"username": admin_user.username, "password": ADMIN_PASSWORD})
    assert resp.status_code == 429
    assert resp.json()["detail"] == "Account temporarily locked"


async def test_lockout_clears_after_expiry(client, session_factory, admin_user):
    async with session_factory() as session:
        user = await session.get(AdminUser, admin_user.id)
        user.failed_logins = 5
        user.locked_until = datetime.now(UTC) - timedelta(seconds=1)  # already expired
        await session.commit()

    resp = await client.post("/auth/login", json={"username": admin_user.username, "password": ADMIN_PASSWORD})
    assert resp.status_code == 200


async def test_successful_login_resets_failed_attempt_counter(client, session_factory, admin_user):
    for _ in range(3):
        await client.post("/auth/login", json={"username": admin_user.username, "password": "wrong"})

    resp = await client.post("/auth/login", json={"username": admin_user.username, "password": ADMIN_PASSWORD})
    assert resp.status_code == 200

    async with session_factory() as session:
        user = await session.get(AdminUser, admin_user.id)
        assert user.failed_logins == 0
        assert user.locked_until is None


async def test_refresh_issues_new_access_token(client, admin_user):
    await client.post("/auth/login", json={"username": admin_user.username, "password": ADMIN_PASSWORD})

    resp = await client.post("/auth/refresh")
    assert resp.status_code == 200
    assert resp.json()["access_token"]


async def test_refresh_rotates_token_and_rejects_reuse_of_old_token(client, admin_user):
    """Each /auth/refresh call rotates the refresh token (revokes the one
    presented, issues a new one). Presenting an already-rotated-away token
    again — as an attacker replaying a stolen token would — must not just be
    rejected but must also revoke the *entire* token family, so the
    legitimate rotated-to token stops working too."""
    login_resp = await client.post("/auth/login", json={"username": admin_user.username, "password": ADMIN_PASSWORD})
    old_token = login_resp.cookies["refresh_token"]

    first_refresh = await client.post("/auth/refresh")
    assert first_refresh.status_code == 200
    new_token = client.cookies["refresh_token"]
    assert new_token != old_token

    # Replay the old, already-rotated-away token.
    client.cookies.set("refresh_token", old_token)
    reuse_resp = await client.post("/auth/refresh")
    assert reuse_resp.status_code == 401
    assert reuse_resp.json()["detail"] == "Invalid or expired refresh token"

    # The theft-detection response should have revoked the whole family,
    # including the token that was legitimately rotated to above.
    client.cookies.set("refresh_token", new_token)
    followup_resp = await client.post("/auth/refresh")
    assert followup_resp.status_code == 401


async def test_refresh_without_cookie_is_rejected(client):
    resp = await client.post("/auth/refresh")
    assert resp.status_code == 401
    assert resp.json()["detail"] == "No refresh token"


async def test_logout_revokes_refresh_token(client, session_factory, admin_user):
    login_resp = await client.post("/auth/login", json={"username": admin_user.username, "password": ADMIN_PASSWORD})
    raw_refresh_token = login_resp.cookies["refresh_token"]

    logout_resp = await client.post("/auth/logout")
    assert logout_resp.status_code == 200

    async with session_factory() as session:
        result = await session.execute(select(RefreshToken).where(RefreshToken.user_id == admin_user.id))
        token = result.scalar_one()
        assert token.revoked is True

    # logout() clears the cookie client-side, so the client's jar no longer
    # holds it. Replay the captured raw value directly to simulate an
    # attacker reusing a captured refresh token after it's been revoked —
    # that must still be rejected regardless of cookie-jar state.
    client.cookies.set("refresh_token", raw_refresh_token)
    refresh_resp = await client.post("/auth/refresh")
    assert refresh_resp.status_code == 401
    assert refresh_resp.json()["detail"] == "Invalid or expired refresh token"


async def test_refresh_token_expired_is_rejected(client, session_factory, admin_user):
    await client.post("/auth/login", json={"username": admin_user.username, "password": ADMIN_PASSWORD})

    async with session_factory() as session:
        result = await session.execute(select(RefreshToken).where(RefreshToken.user_id == admin_user.id))
        token = result.scalar_one()
        token.expires_at = datetime.now(UTC) - timedelta(days=1)
        await session.commit()

    resp = await client.post("/auth/refresh")
    assert resp.status_code == 401
    assert resp.json()["detail"] == "Invalid or expired refresh token"
