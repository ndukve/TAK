import pytest
from fastapi import HTTPException

from api import users as users_module
from api.users import _is_always_enabled, _validate_new_username, _validate_username

# --- Pure validation logic — no docker/network involved. ------------------

@pytest.mark.parametrize("username", [
    "alpha1", "Alpha_1", "alpha-1", "a", "ALPHA123", "alpha_1-2",
])
def test_validate_username_accepts_alphanumeric_hyphen_underscore(username):
    assert _validate_username(username) == username


@pytest.mark.parametrize("username", [
    "alpha 1", "alpha.1", "alpha/1", "", "alpha!1", "alpha@1",
])
def test_validate_username_rejects_invalid_characters(username):
    with pytest.raises(HTTPException) as exc_info:
        _validate_username(username)
    assert exc_info.value.status_code == 400


@pytest.mark.parametrize("username", [
    "alpha1-ATAK", "alpha1-WinTAK", "alpha1-iTAK", "a-b-c-ATAK",
])
def test_validate_new_username_accepts_valid_client_suffix(username):
    assert _validate_new_username(username) == username


@pytest.mark.parametrize("username", [
    "alpha1", "alpha1-atak", "alpha1-ANDROID", "alpha1-ATAK-extra", "-ATAK",
])
def test_validate_new_username_rejects_missing_or_wrong_suffix(username):
    with pytest.raises(HTTPException) as exc_info:
        _validate_new_username(username)
    assert exc_info.value.status_code == 400


def test_base_callsign_strips_known_suffixes():
    assert users_module._base_callsign("alpha1-ATAK") == "alpha1"
    assert users_module._base_callsign("alpha1-WinTAK") == "alpha1"
    assert users_module._base_callsign("alpha1-iTAK") == "alpha1"
    assert users_module._base_callsign("alpha1") == "alpha1"


@pytest.mark.parametrize("username", [
    "efdi-bridge", "efdi-bridge-ATAK", "efdi-bridge-WinTAK", "efdi-bridge-iTAK", "efdi-bridge-Service",
])
def test_efdi_bridge_is_always_enabled(username):
    assert _is_always_enabled(username) is True


def test_other_users_are_not_always_enabled():
    assert _is_always_enabled("alpha1-ATAK") is False


# --- Routes that shell out to the TAK server container — docker mocked. ---

@pytest.fixture
def mock_container(monkeypatch):
    """Patches api.users.run_in_container. Call .set(code, out) to control
    what the next (and all subsequent, until changed) invocations return."""

    state = {"code": 0, "out": "", "calls": []}

    async def _fake_run_in_container(cmd, env=None, workdir=None):
        state["calls"].append({"cmd": cmd, "env": env, "workdir": workdir})
        return state["code"], state["out"]

    monkeypatch.setattr(users_module, "run_in_container", _fake_run_in_container)

    class Controller:
        def set(self, code, out):
            state["code"] = code
            state["out"] = out

        @property
        def calls(self):
            return state["calls"]

    return Controller()


async def test_gen_cert_requires_client_suffix(admin_client, mock_container):
    resp = await admin_client.post("/api/users/gen-cert", json={"username": "alpha1"})
    assert resp.status_code == 400


async def test_gen_cert_success(admin_client, mock_container):
    mock_container.set(0, "cert generated")
    resp = await admin_client.post("/api/users/gen-cert", json={"username": "alpha1-ATAK"})
    assert resp.status_code == 201
    assert resp.json() == {"status": "ok", "output": "cert generated"}


async def test_gen_cert_propagates_container_failure(admin_client, mock_container):
    mock_container.set(1, "boom")
    resp = await admin_client.post("/api/users/gen-cert", json={"username": "alpha1-ATAK"})
    assert resp.status_code == 500
    assert resp.json()["detail"] == "boom"


async def test_gen_cert_readonly_forbidden(readonly_client, mock_container):
    resp = await readonly_client.post("/api/users/gen-cert", json={"username": "alpha1-ATAK"})
    assert resp.status_code == 403


async def test_make_package_creates_field_account(admin_client, mock_container, session_factory):
    from sqlalchemy import select

    from api.models import AdminUser

    mock_container.set(0, "package built")
    resp = await admin_client.post("/api/users/make-package", json={"username": "alpha1-ATAK"})
    assert resp.status_code == 201
    body = resp.json()
    assert body["field_account_created"] is True
    assert body["field_username"] == "alpha1"
    assert body["field_account_password"]

    async with session_factory() as session:
        result = await session.execute(
            select(AdminUser).where(AdminUser.role == "field", AdminUser.owned_callsign == "alpha1")
        )
        assert result.scalar_one_or_none() is not None


async def test_make_package_reuses_existing_field_account(admin_client, mock_container):
    mock_container.set(0, "package built")
    first = await admin_client.post("/api/users/make-package", json={"username": "alpha1-ATAK"})
    assert first.json()["field_account_created"] is True

    second = await admin_client.post("/api/users/make-package", json={"username": "alpha1-WinTAK"})
    assert second.status_code == 201
    body = second.json()
    assert body["field_account_created"] is False
    assert body["field_account_password"] is None


async def test_enable_user(admin_client, mock_container):
    mock_container.set(0, "")
    resp = await admin_client.post("/api/users/enable", json={"username": "alpha1-ATAK"})
    assert resp.status_code == 200
    assert mock_container.calls[-1]["env"] == {
        "USER_CERT_NAME": "alpha1-ATAK",
        "TAK_USER_GROUP": "TAK-USERS",
    }


async def test_disable_user(admin_client, mock_container):
    mock_container.set(0, "")
    resp = await admin_client.post("/api/users/disable", json={"username": "alpha1-ATAK"})
    assert resp.status_code == 200


async def test_disable_efdi_bridge_is_rejected(admin_client, mock_container):
    resp = await admin_client.post("/api/users/disable", json={"username": "efdi-bridge-Service"})
    assert resp.status_code == 409
    assert mock_container.calls == []


async def test_delete_user_route(admin_client, mock_container):
    mock_container.set(0, "")
    resp = await admin_client.delete("/api/users/alpha1-ATAK")
    assert resp.status_code == 200


async def test_delete_efdi_bridge_is_rejected(admin_client, mock_container):
    resp = await admin_client.delete("/api/users/efdi-bridge-ATAK")
    assert resp.status_code == 409
    assert mock_container.calls == []


async def test_delete_user_route_rejects_invalid_username(admin_client, mock_container):
    resp = await admin_client.delete("/api/users/alpha!1")
    assert resp.status_code == 400


async def test_set_password_enforces_complexity_before_container_call(admin_client, mock_container, monkeypatch):
    called = {"value": False}

    async def _spy(*args, **kwargs):
        called["value"] = True
        return 0, ""

    monkeypatch.setattr(users_module, "run_in_container", _spy)

    resp = await admin_client.post("/api/users/set-password", json={"username": "alpha1-ATAK", "password": "short"})
    assert resp.status_code == 400
    assert called["value"] is False


async def test_set_password_success(admin_client, mock_container):
    mock_container.set(0, "")
    resp = await admin_client.post("/api/users/set-password", json={
        "username": "alpha1-ATAK", "password": "ValidPassw0rd!",
    })
    assert resp.status_code == 200


async def test_rename_field_account(admin_client, session_factory):
    from api.deps import pwd_ctx
    from api.models import AdminUser

    async with session_factory() as session:
        session.add(AdminUser(
            username="alpha1", password_hash=pwd_ctx.hash("x"), role="field", owned_callsign="alpha1",
            created_by="test",
        ))
        await session.commit()

    resp = await admin_client.post("/api/users/field-account/alpha1/rename", json={"new_username": "alpha1-renamed"})
    assert resp.status_code == 200
    assert resp.json()["username"] == "alpha1-renamed"


async def test_rename_field_account_not_found(admin_client):
    resp = await admin_client.post("/api/users/field-account/nonexistent/rename", json={"new_username": "whatever"})
    assert resp.status_code == 404


async def test_rename_field_account_username_taken(admin_client, session_factory):
    from api.deps import pwd_ctx
    from api.models import AdminUser

    async with session_factory() as session:
        session.add(AdminUser(
            username="alpha1", password_hash=pwd_ctx.hash("x"), role="field", owned_callsign="alpha1",
            created_by="test",
        ))
        session.add(AdminUser(
            username="taken", password_hash=pwd_ctx.hash("x"), role="field", owned_callsign="bravo1",
            created_by="test",
        ))
        await session.commit()

    resp = await admin_client.post("/api/users/field-account/alpha1/rename", json={"new_username": "taken"})
    assert resp.status_code == 409


async def test_list_users(admin_client, mock_container, session_factory):
    from api.deps import pwd_ctx
    from api.models import AdminUser

    mock_container.set(0, "alpha1-ATAK.zip\nbravo1-WinTAK.zip\n")

    async with session_factory() as session:
        session.add(AdminUser(
            username="alpha1", password_hash=pwd_ctx.hash("x"), role="field", owned_callsign="alpha1",
            created_by="test",
        ))
        await session.commit()

    resp = await admin_client.get("/api/users")
    assert resp.status_code == 200
    users = {u["username"]: u for u in resp.json()["users"]}
    assert users["alpha1-ATAK"]["has_field_account"] is True
    assert users["alpha1-ATAK"]["field_username"] == "alpha1"
    assert users["bravo1-WinTAK"]["has_field_account"] is False
