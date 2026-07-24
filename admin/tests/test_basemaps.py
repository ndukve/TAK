import io
import os
import sqlite3
import time
import zipfile
from contextlib import asynccontextmanager
from urllib.parse import parse_qs, urlsplit

from api import basemaps as basemaps_module

TILE_XML = b"""<?xml version="1.0"?>
<customMapSource>
  <name>Custom Tiles</name>
  <minZoom>2</minZoom>
  <maxZoom>18</maxZoom>
  <tileType>PNG</tileType>
  <url>https://tiles.example.test/{$z}/{$x}/{$y}.png</url>
  <backgroundColor>#000000</backgroundColor>
</customMapSource>
"""

WMS_XML = b"""<?xml version="1.0"?>
<customWmsMapSource>
  <name>Weather Overlay</name>
  <minZoom>1</minZoom>
  <maxZoom>12</maxZoom>
  <tileType>PNG</tileType>
  <version>1.3.0</version>
  <layers>radar</layers>
  <url>https://weather.example.test/wms?</url>
  <coordinatesystem>EPSG:3857</coordinatesystem>
  <aditionalparameters>&amp;TRANSPARENT=TRUE</aditionalparameters>
</customWmsMapSource>
"""


def test_parse_map_source_supports_tile_and_wms_xml():
    tile = basemaps_module.parse_map_source(TILE_XML)
    assert tile["type"] == "MapTile"
    assert tile["name"] == "Custom Tiles"
    assert tile["minZoom"] == 2
    assert tile["maxZoom"] == 18

    wms = basemaps_module.parse_map_source(WMS_XML)
    assert wms["type"] == "WMS"
    assert wms["layers"] == "radar"
    assert wms["coordinateSystem"] == "EPSG:3857"
    assert wms["additionalParameters"] == "&TRANSPARENT=TRUE"


def test_parse_map_source_rejects_entities():
    xml = b'<!DOCTYPE x [<!ENTITY secret SYSTEM "file:///etc/passwd">]><customMapSource><url>&secret;</url></customMapSource>'
    try:
        basemaps_module.parse_map_source(xml)
    except ValueError as exc:
        assert "entity" in str(exc).lower()
    else:
        raise AssertionError("Entity declaration was accepted")


async def test_catalog_includes_presets_and_stored_xml(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(basemaps_module.packages, "MAPS_DIR", str(tmp_path))
    provider = tmp_path / "Custom"
    provider.mkdir()
    (provider / "weather.xml").write_bytes(WMS_XML)

    response = await superadmin_client.get("/api/basemaps/catalog")
    assert response.status_code == 200
    body = response.json()
    assert any(preset["id"] == "esri-rainviewer" for preset in body["presets"])
    assert body["library_sources"] == [
        {
            "id": "library:Custom/weather.xml",
            "name": "Weather Overlay",
            "description": "Stored map source from Custom.",
            "provider": "Custom",
            "kind": "xml",
        }
    ]


async def test_custom_xml_file_is_validated_and_stored(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(basemaps_module.packages, "MAPS_DIR", str(tmp_path))

    response = await superadmin_client.post(
        "/api/basemaps/custom/file",
        data={"name": "Ops Weather"},
        files={"file": ("source.xml", TILE_XML, "text/xml")},
    )
    assert response.status_code == 201
    assert response.json()["id"] == "library:Custom/Ops_Weather.xml"
    stored = (tmp_path / "Custom" / "Ops_Weather.xml").read_bytes()
    assert b"Ops Weather" in stored
    assert b"tiles.example.test" in stored


async def test_custom_xml_url_rejects_private_address(superadmin_client):
    response = await superadmin_client.post(
        "/api/basemaps/custom/url",
        json={"name": "Private", "url": "https://127.0.0.1/source.xml"},
    )
    assert response.status_code == 400
    assert "private or reserved" in response.json()["detail"]


async def test_managed_custom_and_offline_sources_can_be_deleted(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(basemaps_module.packages, "MAPS_DIR", str(tmp_path))
    custom = tmp_path / "Custom"
    custom.mkdir()
    source = custom / "Ops.xml"
    source.write_bytes(TILE_XML)

    response = await superadmin_client.delete("/api/basemaps/library/Custom/Ops.xml")

    assert response.status_code == 200
    assert response.json()["deleted"] == "library:Custom/Ops.xml"
    assert not source.exists()
    bundled = await superadmin_client.delete("/api/basemaps/library/ESRI/World.xml")
    assert bundled.status_code == 400


async def test_connected_euds_come_from_tak_server_without_position_data(tmp_path, monkeypatch):
    (tmp_path / f"{basemaps_module.SERVICE_CERT_NAME}.pem").write_text("cert")
    (tmp_path / f"{basemaps_module.SERVICE_CERT_NAME}.key").write_text("key")
    (tmp_path / f"{basemaps_module.SERVICE_CERT_NAME}.certpass").write_text("password")
    monkeypatch.setattr(basemaps_module, "CERT_DIR", str(tmp_path))
    monkeypatch.setattr(basemaps_module, "_tak_ssl_context", lambda: True)
    calls = []

    class Response:
        def raise_for_status(self):
            return None

        def json(self):
            return {
                "data": [
                    {"clientUid": "ANDROID-2", "callsign": "Bravo"},
                    {"clientUid": "ANDROID-1", "callsign": "Alpha"},
                ]
            }

    class Client:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return None

        async def get(self, path, **kwargs):
            calls.append((path, kwargs))
            return Response()

    monkeypatch.setattr(basemaps_module.httpx, "AsyncClient", Client)

    recipients = await basemaps_module.get_connected_euds()

    assert recipients == [
        {"uid": "ANDROID-1", "callsign": "Alpha", "group": "Ungrouped"},
        {"uid": "ANDROID-2", "callsign": "Bravo", "group": "Ungrouped"},
    ]
    assert calls == [
        (
            "/Marti/api/clientEndPoints",
            {
                "params": {"showCurrentlyConnectedClients": "true", "showMostRecentOnly": "true"},
                "headers": {"Accept": "application/json"},
            },
        )
    ]


async def test_push_expands_preset_and_targets_observed_euds(superadmin_client, monkeypatch):
    contacts = [
        {"uid": "ANDROID-1", "callsign": "Alpha"},
        {"uid": "ANDROID-2", "callsign": "Bravo"},
    ]
    async def _connected():
        return contacts

    monkeypatch.setattr(basemaps_module, "get_connected_euds", _connected)
    captured = {}

    async def _publish(layers, recipients, offline_files=None):
        captured["layers"] = layers
        captured["recipients"] = recipients
        captured["offline_files"] = offline_files
        return {"mission_name": "TAK-Basemaps-test", "pushed_at": "2026-07-17T12:00:00+00:00"}

    monkeypatch.setattr(basemaps_module, "publish_basemap_mission", _publish)

    response = await superadmin_client.post(
        "/api/basemaps/push",
        json={"item_ids": ["esri-noaa-radar"], "recipient_uids": ["ANDROID-2"]},
    )
    assert response.status_code == 200
    assert response.json()["layer_count"] == 3
    assert response.json()["recipients"] == ["Bravo"]
    assert [layer["name"] for layer in captured["layers"]] == [
        "ESRI - World Street Map",
        "ESRI - World Imagery",
        "NOAA - CONUS Radar",
    ]
    assert captured["recipients"] == [contacts[1]]
    assert captured["offline_files"] == []
    assert captured["layers"][1]["after"] == captured["layers"][0]["uid"]
    assert captured["layers"][2]["after"] == captured["layers"][1]["uid"]
    assert captured["layers"][2]["opacity"] == 70
    assert captured["layers"][2]["type"] == "MapTile"
    assert captured["layers"][2]["url"].startswith(basemaps_module.TILE_PROXY_URL)


async def test_push_rejects_stale_recipient_list(superadmin_client, monkeypatch):
    async def _connected():
        return []

    monkeypatch.setattr(basemaps_module, "get_connected_euds", _connected)
    response = await superadmin_client.post(
        "/api/basemaps/push",
        json={"item_ids": ["esri-world-topo"], "recipient_uids": ["OFFLINE"]},
    )
    assert response.status_code == 409
    assert "refresh" in response.json()["detail"].lower()


async def test_publish_uses_native_mission_maplayer_and_invite_apis(tmp_path, monkeypatch):
    (tmp_path / f"{basemaps_module.SERVICE_CERT_NAME}.pem").write_text("cert")
    (tmp_path / f"{basemaps_module.SERVICE_CERT_NAME}.key").write_text("key")
    (tmp_path / f"{basemaps_module.SERVICE_CERT_NAME}.certpass").write_text("password")
    monkeypatch.setattr(basemaps_module, "CERT_DIR", str(tmp_path))
    monkeypatch.setattr(basemaps_module, "_tak_ssl_context", lambda: True)

    async def _authorize():
        return None

    monkeypatch.setattr(basemaps_module, "ensure_service_cert_authorized", _authorize)
    calls = []

    class Response:
        def raise_for_status(self):
            return None

    class Client:
        def __init__(self, **kwargs):
            calls.append(("client", kwargs))

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return None

        async def put(self, path, **kwargs):
            calls.append(("put", path, kwargs))
            return Response()

        async def post(self, path, **kwargs):
            calls.append(("post", path, kwargs))
            return Response()

    monkeypatch.setattr(basemaps_module.httpx, "AsyncClient", Client)
    layer = basemaps_module._mission_layer(
        basemaps_module.BUILTIN_SOURCES["esri-topo"],
        source_id="esri-topo",
        push_id="push123",
    )
    assert layer["type"] == "MapTile"

    result = await basemaps_module.publish_basemap_mission(
        [layer],
        [{"uid": "ANDROID 1", "callsign": "Alpha"}],
    )

    assert result["mission_name"].startswith("TAK-Basemaps-")
    paths = [(call[0], call[1]) for call in calls[1:]]
    assert paths[0][0] == "put"
    assert paths[0][1].startswith("/Marti/api/missions/TAK-Basemaps-")
    assert paths[1][0] == "post" and paths[1][1].endswith("/maplayers")
    assert paths[2][0] == "put" and paths[2][1].endswith("/invite/clientUid/ANDROID%201")
    assert paths[3][0] == "post" and paths[3][1].endswith("/invite")
    assert paths[4][0] == "post" and paths[4][1].endswith("/send")
    assert calls[-1][2]["params"] == [("contacts", "ANDROID 1")]


async def test_basemap_distribution_requires_superadmin(admin_client):
    response = await admin_client.get("/api/basemaps/catalog")
    assert response.status_code == 403


async def test_signed_tile_proxy_caches_valid_upstream_image(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(basemaps_module, "TILE_CACHE_DIR", str(tmp_path))
    basemaps_module._tile_locks.clear()
    calls = []

    class Response:
        content = b"png-tile"
        headers = {"content-type": "image/png"}

        def raise_for_status(self):
            return None

    class Client:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return None

        async def get(self, url, **_kwargs):
            calls.append(url)
            return Response()

    monkeypatch.setattr(basemaps_module.httpx, "AsyncClient", Client)
    token = basemaps_module._proxy_token("esri-topo")

    first = await superadmin_client.get(f"/api/basemaps/tiles/{token}/esri-topo/2/2/1")
    second = await superadmin_client.get(f"/api/basemaps/tiles/{token}/esri-topo/2/2/1")
    rejected = await superadmin_client.get("/api/basemaps/tiles/bad/esri-topo/2/2/1")

    assert first.status_code == second.status_code == 200
    assert first.content == second.content == b"png-tile"
    assert first.headers["cache-control"].startswith("public")
    assert len(calls) == 1
    assert rejected.status_code == 404


async def test_weather_proxy_serves_expired_cache_during_upstream_outage(tmp_path, monkeypatch):
    monkeypatch.setattr(basemaps_module, "TILE_CACHE_DIR", str(tmp_path))
    basemaps_module._tile_locks.clear()
    cache_path = basemaps_module._tile_cache_path("noaa-radar", 2, 2, 1)
    os.makedirs(os.path.dirname(cache_path))
    with open(cache_path, "wb") as cache_file:
        cache_file.write(b"stale-radar")
    old = time.time() - 600
    os.utime(cache_path, (old, old))

    class Client:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return None

        async def get(self, url, **_kwargs):
            raise basemaps_module.httpx.ConnectError("offline", request=basemaps_module.httpx.Request("GET", url))

    monkeypatch.setattr(basemaps_module.httpx, "AsyncClient", Client)

    content, content_type, ttl = await basemaps_module._cached_tile("noaa-radar", 2, 2, 1)

    assert content == b"stale-radar"
    assert content_type == "image/png"
    assert ttl == 60


def test_wms_tiles_are_converted_to_xyz_getmap_requests():
    url = basemaps_module._wms_tile_url(basemaps_module.BUILTIN_SOURCES["noaa-radar"], 3, 2, 3)
    query = parse_qs(urlsplit(url).query)

    assert query["service"] == ["WMS"]
    assert query["request"] == ["GetMap"]
    assert query["layers"] == ["conus_bref_qcd"]
    assert query["crs"] == ["EPSG:3857"]
    assert len(query["bbox"][0].split(",")) == 4


async def test_offline_aoi_builds_valid_mbtiles(superadmin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(basemaps_module.packages, "MAPS_DIR", str(tmp_path))

    async def _tile(_source_id, _zoom, _x, _y):
        return b"tile", "image/png", 300

    monkeypatch.setattr(basemaps_module, "_cached_tile", _tile)
    response = await superadmin_client.post(
        "/api/basemaps/offline/build",
        json={
            "name": "Small AOI",
            "source_id": "esri-topo",
            "west": -1,
            "south": -1,
            "east": 1,
            "north": 1,
            "min_zoom": 1,
            "max_zoom": 1,
        },
    )

    assert response.status_code == 201
    body = response.json()
    path = tmp_path / "Offline" / "Small_AOI.mbtiles"
    assert body["id"] == "offline:Offline/Small_AOI.mbtiles"
    with sqlite3.connect(path) as database:
        assert database.execute("SELECT value FROM metadata WHERE name = 'format'").fetchone() == ("png",)
        assert database.execute("SELECT COUNT(*) FROM tiles").fetchone() == (body["tile_count"],)


def test_offline_mission_package_contains_manifest_and_mbtiles(tmp_path):
    mbtiles = tmp_path / "ops.mbtiles"
    mbtiles.write_bytes(b"offline-data")

    package = basemaps_module._offline_mission_package("TAK-Basemaps-test", [str(mbtiles)])

    with zipfile.ZipFile(io.BytesIO(package)) as archive:
        assert set(archive.namelist()) == {"MANIFEST/manifest.xml", "content/ops.mbtiles"}
        assert b'zipEntry="content/ops.mbtiles"' in archive.read("MANIFEST/manifest.xml")
        assert archive.read("content/ops.mbtiles") == b"offline-data"


async def test_distribution_history_is_idempotent_tracks_acceptance_and_deletes(
    superadmin_client,
    monkeypatch,
):
    async def _connected():
        return [{"uid": "ANDROID-1", "callsign": "Alpha", "group": "Blue"}]

    publish_calls = []

    async def _publish(layers, recipients, offline_files=None):
        publish_calls.append((layers, recipients, offline_files))
        return {"mission_name": "TAK-Basemaps-history", "pushed_at": "2026-07-17T12:00:00+00:00"}

    class Response:
        def raise_for_status(self):
            return None

        def json(self):
            return {"data": [{"clientUid": "ANDROID-1"}, {"clientUid": "SOMEONE-ELSE"}]}

    class Client:
        async def get(self, _path):
            return Response()

    @asynccontextmanager
    async def _client():
        yield Client()

    deleted = []

    async def _delete(mission_name):
        deleted.append(mission_name)

    monkeypatch.setattr(basemaps_module, "get_connected_euds", _connected)
    monkeypatch.setattr(basemaps_module, "publish_basemap_mission", _publish)
    monkeypatch.setattr(basemaps_module, "_tak_client", _client)
    monkeypatch.setattr(basemaps_module, "delete_basemap_mission", _delete)
    payload = {
        "item_ids": ["esri-world-topo"],
        "recipient_uids": ["ANDROID-1"],
        "overlay_opacity": 42,
        "request_id": "history-request-123",
    }

    first = await superadmin_client.post("/api/basemaps/push", json=payload)
    repeated = await superadmin_client.post("/api/basemaps/push", json=payload)
    assert first.status_code == repeated.status_code == 200
    assert first.json()["id"] == repeated.json()["id"]
    assert first.json()["overlay_opacity"] == 42
    assert len(publish_calls) == 1

    distribution_id = first.json()["id"]
    refreshed = await superadmin_client.post(f"/api/basemaps/history/{distribution_id}/refresh")
    assert refreshed.status_code == 200
    assert refreshed.json()["accepted_count"] == 1

    history = await superadmin_client.get("/api/basemaps/history")
    assert history.json()["distributions"][0]["accepted_count"] == 1

    removed = await superadmin_client.delete(f"/api/basemaps/history/{distribution_id}")
    assert removed.status_code == 200
    assert removed.json()["status"] == "deleted"
    assert deleted == ["TAK-Basemaps-history"]


async def test_diagnostics_reports_proxy_certificate_cache_and_tak_status(
    superadmin_client,
    tmp_path,
    monkeypatch,
):
    for suffix in ("pem", "key", "certpass"):
        (tmp_path / f"{basemaps_module.SERVICE_CERT_NAME}.{suffix}").write_text("ready")
    monkeypatch.setattr(basemaps_module, "CERT_DIR", str(tmp_path))
    monkeypatch.setattr(basemaps_module, "TILE_CACHE_DIR", str(tmp_path))
    monkeypatch.setattr(basemaps_module, "TILE_PROXY_URL", "https://tak.example.test:8889")

    async def _connected():
        return [{"uid": "ANDROID-1", "callsign": "Alpha", "group": "Blue"}]

    monkeypatch.setattr(basemaps_module, "get_connected_euds", _connected)
    response = await superadmin_client.get("/api/basemaps/diagnostics")

    assert response.status_code == 200
    body = response.json()
    assert body["ready"] is True
    assert body["checks"]["service_certificate"]["ready"] is True
    assert body["checks"]["tile_proxy"]["ready"] is True
    assert body["checks"]["tile_cache"]["ready"] is True
    assert body["checks"]["tak_api"]["connected_euds"] == 1
    assert body["sample_tile_url"].startswith("https://tak.example.test:8889/")
