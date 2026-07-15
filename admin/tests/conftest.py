import os

# Must be set before any `api.*` module is imported — db.py and deps.py read
# these at import time and raise/KeyError if they're missing.
os.environ.setdefault("POSTGRES_USER", "test")
os.environ.setdefault("POSTGRES_PASSWORD", "test")
os.environ.setdefault("ADMIN_SECRET_KEY", "x" * 64)

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from api import password_policy
from api.db import Base, get_db
from api.deps import pwd_ctx
from api.main import app
from api.models import AdminUser


@pytest.fixture(autouse=True)
def _no_network_password_check(monkeypatch):
    """validate_password() normally calls the real Have I Been Pwned API.
    Tests should exercise the complexity rules deterministically without
    depending on outbound network access, so treat every password as
    unbreached — the complexity check in validate_password still runs for
    real."""
    async def _fake_hibp(password: str) -> int:
        return 0

    monkeypatch.setattr(password_policy, "_hibp_pwned", _fake_hibp)


@pytest_asyncio.fixture
async def db_engine():
    """Fresh in-memory SQLite database per test. StaticPool keeps the same
    connection alive for the engine's lifetime — plain in-memory SQLite is
    otherwise per-connection and tables would vanish between uses."""
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture
def session_factory(db_engine):
    return async_sessionmaker(db_engine, expire_on_commit=False)


@pytest_asyncio.fixture
async def db_session(session_factory):
    async with session_factory() as session:
        yield session


@pytest_asyncio.fixture
async def client(session_factory):
    """Unauthenticated async test client wired to the SQLite test database."""

    async def _override_get_db():
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = _override_get_db
    transport = ASGITransport(app=app)
    # https:// (not http://) — /auth/login sets the refresh_token cookie with
    # Secure=True, and httpx's cookie jar (correctly) won't resend a Secure
    # cookie back to a plain http:// origin on the next request.
    async with AsyncClient(transport=transport, base_url="https://test") as ac:
        yield ac
    app.dependency_overrides.clear()


async def _make_user(session_factory, username, password, role, **kwargs):
    async with session_factory() as session:
        user = AdminUser(
            username=username,
            password_hash=pwd_ctx.hash(password),
            role=role,
            created_by="test",
            **kwargs,
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        return user


SUPERADMIN_PASSWORD = "SuperSecret123!"
ADMIN_PASSWORD = "AdminSecret123!"
READONLY_PASSWORD = "ReadonlySecret123!"


@pytest_asyncio.fixture
async def superadmin_user(session_factory):
    return await _make_user(session_factory, "superadmin1", SUPERADMIN_PASSWORD, "superadmin")


@pytest_asyncio.fixture
async def admin_user(session_factory):
    return await _make_user(session_factory, "admin1", ADMIN_PASSWORD, "admin")


@pytest_asyncio.fixture
async def readonly_user(session_factory):
    return await _make_user(session_factory, "readonly1", READONLY_PASSWORD, "readonly")


async def _login(client, username, password):
    return await client.post("/auth/login", json={"username": username, "password": password})


@pytest_asyncio.fixture
async def superadmin_client(client, superadmin_user):
    resp = await _login(client, superadmin_user.username, SUPERADMIN_PASSWORD)
    token = resp.json()["access_token"]
    client.headers["Authorization"] = f"Bearer {token}"
    return client


@pytest_asyncio.fixture
async def admin_client(client, admin_user):
    resp = await _login(client, admin_user.username, ADMIN_PASSWORD)
    token = resp.json()["access_token"]
    client.headers["Authorization"] = f"Bearer {token}"
    return client


@pytest_asyncio.fixture
async def readonly_client(client, readonly_user):
    resp = await _login(client, readonly_user.username, READONLY_PASSWORD)
    token = resp.json()["access_token"]
    client.headers["Authorization"] = f"Bearer {token}"
    return client
