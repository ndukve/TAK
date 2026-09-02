from pathlib import Path

import pytest

from api import live_map as live_map_module
from api.live_map import _affiliation, _parse_events
from api.models import ReplaySettings


def test_affiliation_maps_known_codes():
    assert _affiliation("a-f-G-U-C") == "friendly"
    assert _affiliation("a-h-G") == "hostile"
    assert _affiliation("a-n-G") == "neutral"
    assert _affiliation("a-u-G") == "unknown"


def test_proxy_csp_allows_live_map_tiles():
    repo_root = Path(__file__).resolve().parents[2]
    widget = (repo_root / "admin/ui/src/components/LiveMapWidget.tsx").read_text()
    nginx = (repo_root / "admin/nginx/nginx.conf").read_text()
    assert "tile.openstreetmap.org" in widget
    assert "https://tile.openstreetmap.org" in nginx


def test_affiliation_unknown_for_non_atom_types():
    assert _affiliation("b-m-p-w") == "unknown"


def test_parse_events_extracts_uid_and_position():
    xml = b"<event uid='u1' type='a-f-G-U-C' time='t' stale='s'><point lat='1.5' lon='2.5' hae='10'/><detail><contact callsign='ALPHA'/></detail></event>"
    contacts, tail = _parse_events(xml)
    assert tail == b""
    assert len(contacts) == 1
    c = contacts[0]
    assert c["uid"] == "u1"
    assert c["callsign"] == "ALPHA"
    assert c["lat"] == 1.5
    assert c["lon"] == 2.5
    assert c["affiliation"] == "friendly"


def test_parse_events_handles_multiple_concatenated_events():
    one = b"<event uid='u1' type='a-f-G'><point lat='1' lon='1'/></event>"
    two = b"<event uid='u2' type='a-h-G'><point lat='2' lon='2'/></event>"
    contacts, tail = _parse_events(one + two)
    assert tail == b""
    assert {c["uid"] for c in contacts} == {"u1", "u2"}


def test_parse_events_leaves_incomplete_tail():
    complete = b"<event uid='u1' type='a-f-G'><point lat='1' lon='1'/></event>"
    partial = b"<event uid='u2' type='a-f-G'><point lat"
    contacts, tail = _parse_events(complete + partial)
    assert len(contacts) == 1
    assert tail == partial


def test_parse_events_skips_events_without_point():
    xml = b"<event uid='u1' type='a-f-G'><detail/></event>"
    contacts, tail = _parse_events(xml)
    assert contacts == []


async def test_get_status_defaults(admin_client):
    resp = await admin_client.get("/api/live-map/status")
    assert resp.status_code == 200
    data = resp.json()
    assert data["service_cert_ready"] is False
    assert data["tracking"] is False
    assert data["contact_count"] == 0


async def test_status_forbidden_for_readonly(readonly_client):
    resp = await readonly_client.get("/api/live-map/status")
    assert resp.status_code == 403


async def test_get_contacts_empty(admin_client):
    resp = await admin_client.get("/api/live-map/contacts")
    assert resp.status_code == 200
    assert resp.json()["contacts"] == []


async def test_start_requires_setup_first(superadmin_client):
    resp = await superadmin_client.post("/api/live-map/start")
    assert resp.status_code == 400


async def test_start_forbidden_for_admin(admin_client):
    resp = await admin_client.post("/api/live-map/start")
    assert resp.status_code == 403


async def test_stop_when_not_tracking_is_a_noop(superadmin_client):
    resp = await superadmin_client.post("/api/live-map/stop")
    assert resp.status_code == 200
    assert resp.json()["status"] == "not_tracking"


@pytest.fixture
def mock_cot_connection(monkeypatch, tmp_path):
    """Feeds the tracker one CoT event then blocks, mirroring the replay
    suite's mock_cot_connection — see admin/tests/test_replay.py."""
    import asyncio

    xml = b"<event uid='u1' type='a-f-G-U-C'><point lat='1.5' lon='2.5'/><detail><contact callsign='ALPHA'/></detail></event>"

    class FakeReader:
        def __init__(self):
            self._sent = False

        async def read(self, n):
            if not self._sent:
                self._sent = True
                return xml
            await asyncio.sleep(3600)
            return b""

    class FakeWriter:
        def close(self):
            pass

    async def _fake_open(cert_path, key_path, key_password, server_addr):
        return FakeReader(), FakeWriter()

    monkeypatch.setattr(live_map_module, "_open_cot_connection", _fake_open)
    (tmp_path / f"{live_map_module.SERVICE_CERT_NAME}.certpass").write_text("fake-password")
    monkeypatch.setattr(live_map_module, "CERT_DIR", str(tmp_path))
    (tmp_path / f"{live_map_module.SERVICE_CERT_NAME}.pem").write_text("fake-cert")
    (tmp_path / f"{live_map_module.SERVICE_CERT_NAME}.key").write_text("fake-key")


async def test_start_tracking_picks_up_contacts(superadmin_client, mock_cot_connection, session_factory, monkeypatch):
    authorized = False

    async def _authorize():
        nonlocal authorized
        authorized = True

    monkeypatch.setattr(live_map_module, "ensure_service_cert_authorized", _authorize)
    async with session_factory() as session:
        session.add(ReplaySettings(id="singleton", service_cert_ready=True))
        await session.commit()

    resp = await superadmin_client.post("/api/live-map/start")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
    assert authorized is True

    # give the background track loop a tick to consume the fake event
    import asyncio
    await asyncio.sleep(0.1)

    contacts = await superadmin_client.get("/api/live-map/contacts")
    data = contacts.json()["contacts"]
    assert len(data) == 1
    assert data[0]["uid"] == "u1"
    assert data[0]["callsign"] == "ALPHA"

    second = await superadmin_client.post("/api/live-map/start")
    assert second.json()["status"] == "already_tracking"

    stop_resp = await superadmin_client.post("/api/live-map/stop")
    assert stop_resp.status_code == 200
