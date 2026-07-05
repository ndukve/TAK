from sqlalchemy import select

from api.models import AdminUser

from .conftest import ADMIN_PASSWORD

NEW_USER_PASSWORD = "BrandNewSecret123!"


async def test_superadmin_can_list_admin_users(superadmin_client, superadmin_user, admin_user):
    resp = await superadmin_client.get("/api/admin-users")
    assert resp.status_code == 200
    usernames = {u["username"] for u in resp.json()["users"]}
    assert {superadmin_user.username, admin_user.username} <= usernames


async def test_non_superadmin_gets_403_listing_admin_users(admin_client):
    resp = await admin_client.get("/api/admin-users")
    assert resp.status_code == 403
    assert resp.json()["detail"] == "Insufficient permissions"


async def test_readonly_gets_403_on_superadmin_only_route(readonly_client):
    resp = await readonly_client.post("/api/admin-users", json={
        "username": "newperson", "password": NEW_USER_PASSWORD, "role": "admin",
    })
    assert resp.status_code == 403
    assert resp.json()["detail"] == "Insufficient permissions"


async def test_unauthenticated_request_is_401(client):
    resp = await client.get("/api/admin-users")
    assert resp.status_code == 401


async def test_superadmin_creates_admin_user(superadmin_client, session_factory):
    resp = await superadmin_client.post("/api/admin-users", json={
        "username": "newadmin", "password": NEW_USER_PASSWORD, "role": "admin",
    })
    assert resp.status_code == 201
    body = resp.json()
    assert body["username"] == "newadmin"
    assert body["role"] == "admin"

    async with session_factory() as session:
        result = await session.execute(select(AdminUser).where(AdminUser.username == "newadmin"))
        assert result.scalar_one_or_none() is not None


async def test_create_user_rejects_invalid_role(superadmin_client):
    resp = await superadmin_client.post("/api/admin-users", json={
        "username": "newadmin2", "password": NEW_USER_PASSWORD, "role": "field",
    })
    assert resp.status_code == 400


async def test_create_user_rejects_duplicate_username(superadmin_client, admin_user):
    resp = await superadmin_client.post("/api/admin-users", json={
        "username": admin_user.username, "password": NEW_USER_PASSWORD, "role": "admin",
    })
    assert resp.status_code == 409


async def test_create_user_rejects_weak_password(superadmin_client):
    resp = await superadmin_client.post("/api/admin-users", json={
        "username": "weakpassuser", "password": "short", "role": "admin",
    })
    assert resp.status_code == 400


async def test_patch_user_changes_role(superadmin_client, admin_user):
    resp = await superadmin_client.patch(f"/api/admin-users/{admin_user.id}", json={"role": "superadmin"})
    assert resp.status_code == 200
    assert resp.json()["role"] == "superadmin"


async def test_patch_user_cannot_change_own_role(superadmin_client, superadmin_user):
    resp = await superadmin_client.patch(f"/api/admin-users/{superadmin_user.id}", json={"role": "admin"})
    assert resp.status_code == 400
    assert resp.json()["detail"] == "Cannot change your own role"


async def test_patch_user_deactivates(superadmin_client, session_factory, admin_user):
    resp = await superadmin_client.patch(f"/api/admin-users/{admin_user.id}", json={"is_active": False})
    assert resp.status_code == 200

    async with session_factory() as session:
        user = await session.get(AdminUser, admin_user.id)
        assert user.is_active is False


async def test_patch_user_not_found(superadmin_client):
    resp = await superadmin_client.patch("/api/admin-users/does-not-exist", json={"is_active": False})
    assert resp.status_code == 404


async def test_non_superadmin_gets_403_patching_user(admin_client, admin_user):
    resp = await admin_client.patch(f"/api/admin-users/{admin_user.id}", json={"is_active": False})
    assert resp.status_code == 403


async def test_delete_user(superadmin_client, session_factory, admin_user):
    resp = await superadmin_client.delete(f"/api/admin-users/{admin_user.id}")
    assert resp.status_code == 200
    assert resp.json()["status"] == "deleted"

    async with session_factory() as session:
        assert await session.get(AdminUser, admin_user.id) is None


async def test_cannot_delete_self(superadmin_client, superadmin_user):
    resp = await superadmin_client.delete(f"/api/admin-users/{superadmin_user.id}")
    assert resp.status_code == 400
    assert resp.json()["detail"] == "Cannot delete yourself"


async def test_non_superadmin_gets_403_deleting_user(admin_client, admin_user):
    resp = await admin_client.delete(f"/api/admin-users/{admin_user.id}")
    assert resp.status_code == 403


async def test_change_own_password_success(admin_client):
    resp = await admin_client.post("/api/admin-users/me/change-password", json={
        "current_password": ADMIN_PASSWORD, "new_password": "AnotherSecret456!",
    })
    assert resp.status_code == 200


async def test_change_own_password_wrong_current_password(admin_client):
    resp = await admin_client.post("/api/admin-users/me/change-password", json={
        "current_password": "not-the-right-password", "new_password": "AnotherSecret456!",
    })
    assert resp.status_code == 400
    assert resp.json()["detail"] == "Current password is incorrect"


async def test_change_own_password_rejects_weak_new_password(admin_client):
    resp = await admin_client.post("/api/admin-users/me/change-password", json={
        "current_password": ADMIN_PASSWORD, "new_password": "short",
    })
    assert resp.status_code == 400
