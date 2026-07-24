import hashlib

from api import packages as packages_module


async def test_upload_plugin_checksum_mismatch_does_not_delete_existing_file(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "PLUGINS_DIR", str(tmp_path))

    good = b"real plugin bytes"
    res = await superadmin_client.post(
        "/api/plugins",
        files={"file": ("test.zip", good, "application/zip")},
    )
    assert res.status_code == 201
    assert (tmp_path / "test.zip").read_bytes() == good

    res2 = await superadmin_client.post(
        "/api/plugins",
        files={"file": ("test.zip", b"attacker-controlled bytes", "application/zip")},
        data={"expected_sha256": "0" * 64},
    )
    assert res2.status_code == 400

    assert (tmp_path / "test.zip").exists()
    assert (tmp_path / "test.zip").read_bytes() == good


async def test_upload_plugin_checksum_match_succeeds(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "PLUGINS_DIR", str(tmp_path))

    data = b"plugin bytes"
    digest = hashlib.sha256(data).hexdigest()
    res = await superadmin_client.post(
        "/api/plugins",
        files={"file": ("ok.zip", data, "application/zip")},
        data={"expected_sha256": digest},
    )
    assert res.status_code == 201
    assert (tmp_path / "ok.zip").read_bytes() == data
    assert (tmp_path / "ok.zip.sha256").read_text().strip() == digest


async def test_upload_map_xml_succeeds(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "MAPS_DIR", str(tmp_path))
    xml = b"<customMapSource name='esri'></customMapSource>"
    res = await superadmin_client.post(
        "/api/maps?provider=esri",
        files={"file": ("esri.xml", xml, "text/xml")},
    )
    assert res.status_code == 201
    assert (tmp_path / "esri" / "esri.xml").read_bytes() == xml


async def test_upload_map_mbtiles_streams_to_disk(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "MAPS_DIR", str(tmp_path))
    data = b"fake mbtiles sqlite bytes" * 1000
    res = await superadmin_client.post(
        "/api/maps?provider=lietuva50k",
        files={"file": ("Lietuva_50K.mbtiles", data, "application/octet-stream")},
    )
    assert res.status_code == 201
    body = res.json()
    assert body["sha256"] == hashlib.sha256(data).hexdigest()
    dest = tmp_path / "lietuva50k" / "Lietuva_50K.mbtiles"
    assert dest.read_bytes() == data
    assert (tmp_path / "lietuva50k" / "Lietuva_50K.mbtiles.sha256").read_text().strip() == body["sha256"]


async def test_chunked_map_upload_resumes_and_finalizes(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "MAPS_DIR", str(tmp_path))
    data = b"resumable mbtiles bytes"
    init_body = {
        "provider": "lietuva",
        "filename": "Lietuva.mbtiles",
        "total_size": len(data),
        "fingerprint": "22:123456",
    }

    initialized = await superadmin_client.post("/api/maps/uploads", json=init_body)
    assert initialized.status_code == 200
    assert initialized.json() == {"offset": 0, "complete": False}

    first = await superadmin_client.put(
        f"/api/maps/uploads/lietuva/Lietuva.mbtiles?offset=0&total_size={len(data)}&fingerprint=22%3A123456",
        content=data[:10],
    )
    assert first.status_code == 200
    assert first.json() == {"offset": 10, "complete": False}

    resumed = await superadmin_client.post("/api/maps/uploads", json=init_body)
    assert resumed.json() == {"offset": 10, "complete": False}

    final = await superadmin_client.put(
        f"/api/maps/uploads/lietuva/Lietuva.mbtiles?offset=10&total_size={len(data)}&fingerprint=22%3A123456",
        content=data[10:],
    )
    assert final.status_code == 200
    assert final.json()["complete"] is True
    assert final.json()["sha256"] == hashlib.sha256(data).hexdigest()
    assert (tmp_path / "lietuva" / "Lietuva.mbtiles").read_bytes() == data

    recovered = await superadmin_client.post("/api/maps/uploads", json=init_body)
    assert recovered.json()["offset"] == len(data)
    assert recovered.json()["complete"] is True


async def test_chunked_map_upload_rejects_wrong_resume_offset(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "MAPS_DIR", str(tmp_path))
    body = {"provider": "test", "filename": "test.xml", "total_size": 10, "fingerprint": "10:1"}
    await superadmin_client.post("/api/maps/uploads", json=body)

    res = await superadmin_client.put(
        "/api/maps/uploads/test/test.xml?offset=5&total_size=10&fingerprint=10%3A1",
        content=b"12345",
    )
    assert res.status_code == 409
    assert "byte 0" in res.json()["detail"]


async def test_upload_map_mbtiles_rejects_oversized(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "MAPS_DIR", str(tmp_path))
    monkeypatch.setattr(packages_module, "MAX_MBTILES_BYTES", 100)
    data = b"x" * 200
    res = await superadmin_client.post(
        "/api/maps?provider=huge",
        files={"file": ("huge.mbtiles", data, "application/octet-stream")},
    )
    assert res.status_code == 413
    assert not (tmp_path / "huge" / "huge.mbtiles").exists()


async def test_upload_map_rejects_unknown_extension(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "MAPS_DIR", str(tmp_path))
    res = await superadmin_client.post(
        "/api/maps?provider=bad",
        files={"file": ("map.zip", b"data", "application/zip")},
    )
    assert res.status_code == 400


async def test_list_maps_returns_xml_and_mbtiles_with_kind(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "MAPS_DIR", str(tmp_path))
    (tmp_path / "provA").mkdir()
    (tmp_path / "provA" / "source.xml").write_bytes(b"<xml/>")
    (tmp_path / "provA" / "offline.mbtiles").write_bytes(b"tiles")

    res = await superadmin_client.get("/api/maps")
    assert res.status_code == 200
    maps = {m["filename"]: m["kind"] for m in res.json()["maps"]}
    assert maps == {"source.xml": "xml", "offline.mbtiles": "mbtiles"}


async def test_download_map_mbtiles_uses_octet_stream(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(packages_module, "MAPS_DIR", str(tmp_path))
    (tmp_path / "provA").mkdir()
    (tmp_path / "provA" / "offline.mbtiles").write_bytes(b"tile-bytes")

    res = await superadmin_client.get("/api/maps/provA/offline.mbtiles/download")
    assert res.status_code == 200
    assert res.headers["content-type"] == "application/octet-stream"
    assert res.content == b"tile-bytes"
