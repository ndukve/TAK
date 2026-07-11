from api import branding as branding_module


async def test_get_branding_returns_defaults_when_no_row_exists(client):
    res = await client.get("/api/branding")
    assert res.status_code == 200
    data = res.json()
    assert data["org_name"] == "TAK Admin"
    assert data["accent_fill"] == "#2dd4bf"
    assert data["logo_url"] is None


async def test_get_branding_is_public_no_auth_required(client):
    res = await client.get("/api/branding")
    assert res.status_code == 200


async def test_put_branding_updates_org_name_and_colors(superadmin_client):
    res = await superadmin_client.put("/api/branding", json={"org_name": "My Org", "accent_fill": "#112233"})
    assert res.status_code == 200
    data = res.json()
    assert data["org_name"] == "My Org"
    assert data["accent_fill"] == "#112233"

    res2 = await superadmin_client.get("/api/branding")
    assert res2.json()["org_name"] == "My Org"


async def test_put_branding_rejects_invalid_hex_color(superadmin_client):
    res = await superadmin_client.put("/api/branding", json={"accent_fill": "not-a-color"})
    assert res.status_code == 400


async def test_put_branding_rejects_empty_org_name(superadmin_client):
    res = await superadmin_client.put("/api/branding", json={"org_name": ""})
    assert res.status_code == 400


async def test_put_branding_forbidden_for_admin_role(admin_client):
    res = await admin_client.put("/api/branding", json={"org_name": "Nope"})
    assert res.status_code == 403


async def test_put_branding_forbidden_for_readonly_role(readonly_client):
    res = await readonly_client.put("/api/branding", json={"org_name": "Nope"})
    assert res.status_code == 403


async def test_put_branding_forbidden_unauthenticated(client):
    res = await client.put("/api/branding", json={"org_name": "Nope"})
    assert res.status_code == 401


async def test_upload_logo_success(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(branding_module, "LOGO_DIR", str(tmp_path))
    res = await superadmin_client.post(
        "/api/branding/logo",
        files={"file": ("logo.png", b"\x89PNG\r\n\x1a\n" + b"0" * 100, "image/png")},
    )
    assert res.status_code == 201
    data = res.json()
    assert data["logo_url"] == "/api/branding/logo/logo.png"
    assert (tmp_path / "logo.png").exists()


async def test_upload_logo_rejects_non_image_extension(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(branding_module, "LOGO_DIR", str(tmp_path))
    res = await superadmin_client.post(
        "/api/branding/logo",
        files={"file": ("evil.exe", b"not an image", "application/octet-stream")},
    )
    assert res.status_code == 400


async def test_upload_logo_rejects_oversized_file(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(branding_module, "LOGO_DIR", str(tmp_path))
    too_big = b"0" * (branding_module.MAX_LOGO_BYTES + 1)
    res = await superadmin_client.post(
        "/api/branding/logo",
        files={"file": ("logo.png", too_big, "image/png")},
    )
    assert res.status_code == 413


async def test_upload_logo_replaces_previous_file_different_extension(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(branding_module, "LOGO_DIR", str(tmp_path))
    await superadmin_client.post("/api/branding/logo", files={"file": ("logo.png", b"png-data", "image/png")})
    assert (tmp_path / "logo.png").exists()

    res = await superadmin_client.post("/api/branding/logo", files={"file": ("logo.jpg", b"jpg-data", "image/jpeg")})
    assert res.status_code == 201
    assert not (tmp_path / "logo.png").exists()
    assert (tmp_path / "logo.jpg").exists()


async def test_delete_logo_removes_file_and_clears_filename(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(branding_module, "LOGO_DIR", str(tmp_path))
    await superadmin_client.post("/api/branding/logo", files={"file": ("logo.png", b"png-data", "image/png")})

    res = await superadmin_client.delete("/api/branding/logo")
    assert res.status_code == 200
    assert res.json()["logo_url"] is None
    assert not (tmp_path / "logo.png").exists()


async def test_get_branding_omits_logo_url_when_file_missing_on_disk(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(branding_module, "LOGO_DIR", str(tmp_path))
    await superadmin_client.post("/api/branding/logo", files={"file": ("logo.png", b"png-data", "image/png")})
    (tmp_path / "logo.png").unlink()

    res = await superadmin_client.get("/api/branding")
    assert res.json()["logo_url"] is None


async def test_serve_logo_returns_file(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(branding_module, "LOGO_DIR", str(tmp_path))
    await superadmin_client.post("/api/branding/logo", files={"file": ("logo.png", b"png-bytes", "image/png")})

    res = await superadmin_client.get("/api/branding/logo/logo.png")
    assert res.status_code == 200
    assert res.content == b"png-bytes"


async def test_upload_logo_forbidden_for_non_superadmin(admin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(branding_module, "LOGO_DIR", str(tmp_path))
    res = await admin_client.post("/api/branding/logo", files={"file": ("logo.png", b"data", "image/png")})
    assert res.status_code == 403
