import asyncio

import pytest

from api import replay as replay_module
from api.models import ReplayChunk


@pytest.fixture
def mock_container(monkeypatch):
    """Patches api.replay.run_in_container. Call .set(code, out) to control
    what the next (and all subsequent, until changed) invocations return."""
    state = {"code": 0, "out": "", "calls": []}

    async def _fake_run_in_container(cmd, env=None, workdir=None):
        state["calls"].append({"cmd": cmd, "env": env, "workdir": workdir})
        return state["code"], state["out"]

    monkeypatch.setattr(replay_module, "run_in_container", _fake_run_in_container)

    class Controller:
        @property
        def calls(self):
            return state["calls"]

        def set(self, code, out):
            state["code"] = code
            state["out"] = out
    return Controller()


async def test_get_status_defaults(superadmin_client):
    resp = await superadmin_client.get("/api/replay/status")
    assert resp.status_code == 200
    data = resp.json()
    assert data["recording"] is False
    assert data["service_cert_ready"] is False
    assert data["settings"]["max_disk_mb"] == 0
    assert data["settings"]["chunk_minutes"] == 15


async def test_status_forbidden_for_admin(admin_client):
    resp = await admin_client.get("/api/replay/status")
    assert resp.status_code == 403


async def test_update_settings(superadmin_client):
    resp = await superadmin_client.put("/api/replay/settings", json={"max_disk_mb": 500, "chunk_minutes": 30})
    assert resp.status_code == 200

    status = await superadmin_client.get("/api/replay/status")
    assert status.json()["settings"]["max_disk_mb"] == 500
    assert status.json()["settings"]["chunk_minutes"] == 30


async def test_update_settings_rejects_negative(superadmin_client):
    resp = await superadmin_client.put("/api/replay/settings", json={"max_disk_mb": -1})
    assert resp.status_code == 400


async def test_list_chunks_empty(superadmin_client):
    resp = await superadmin_client.get("/api/replay/chunks")
    assert resp.status_code == 200
    assert resp.json()["chunks"] == []


async def test_list_chunks_returns_created_chunk(superadmin_client, session_factory):
    async with session_factory() as session:
        session.add(ReplayChunk(id="chunk-1", event_count=42, size_bytes=1024))
        await session.commit()

    resp = await superadmin_client.get("/api/replay/chunks")
    chunks = resp.json()["chunks"]
    assert len(chunks) == 1
    assert chunks[0]["id"] == "chunk-1"
    assert chunks[0]["event_count"] == 42


async def test_delete_chunk_not_found(superadmin_client):
    resp = await superadmin_client.delete("/api/replay/chunks/does-not-exist")
    assert resp.status_code == 404


async def test_delete_chunk_removes_row(superadmin_client, session_factory):
    async with session_factory() as session:
        session.add(ReplayChunk(id="chunk-2"))
        await session.commit()

    resp = await superadmin_client.delete("/api/replay/chunks/chunk-2")
    assert resp.status_code == 200

    async with session_factory() as session:
        chunk = await session.get(ReplayChunk, "chunk-2")
        assert chunk is None


async def test_setup_generates_cert_and_marks_ready(superadmin_client, mock_container, session_factory):
    mock_container.set(0, "cert generated")
    resp = await superadmin_client.post("/api/replay/setup")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"

    status = await superadmin_client.get("/api/replay/status")
    assert status.json()["service_cert_ready"] is True
    assert mock_container.calls == [
        {
            "cmd": ["bash", "/opt/scripts/gen_client_cert.sh"],
            "env": {"CLIENT_CERT_NAME": "replay-Service"},
            "workdir": None,
        },
        {
            "cmd": ["bash", "/opt/scripts/enable_user.sh"],
            "env": {"USER_CERT_NAME": "replay-Service", "TAK_USER_GROUP": "TAK-USERS"},
            "workdir": None,
        },
    ]


async def test_setup_is_idempotent(superadmin_client, mock_container):
    mock_container.set(0, "cert generated")
    first = await superadmin_client.post("/api/replay/setup")
    assert first.status_code == 200

    second = await superadmin_client.post("/api/replay/setup")
    assert second.status_code == 200
    assert second.json()["status"] == "already_ready"
    assert mock_container.calls[-1]["cmd"] == ["bash", "/opt/scripts/enable_user.sh"]


async def test_setup_propagates_container_failure(superadmin_client, mock_container):
    mock_container.set(1, "openssl error")
    resp = await superadmin_client.post("/api/replay/setup")
    assert resp.status_code == 502


from api import replay_recorder as recorder_module  # noqa: E402


@pytest.fixture
def mock_cot_connection(monkeypatch, tmp_path):
    """Patches replay_recorder._open_cot_connection with a fake reader/writer
    pair that yields one CoT XML byte chunk then EOF, and points chunk/cert
    storage at tmp_path so no real TAK server or on-disk cert is needed."""
    events = [b"<event uid='test-1'/>", b""]

    class FakeReader:
        """Blocks past the record loop's 1s wait_for timeout so tests get a
        window to observe is_recording()==True before calling stop()."""
        def __init__(self):
            self._events = list(events)

        async def read(self, n):
            await asyncio.sleep(3600)
            return self._events.pop(0) if self._events else b""

    class FakeWriter:
        def close(self):
            pass

        async def drain(self):
            pass

        def write(self, data):
            pass

    async def _fake_open(cert_path, key_path, key_password, server_addr):
        return FakeReader(), FakeWriter()

    monkeypatch.setattr(recorder_module, "_open_cot_connection", _fake_open)
    monkeypatch.setattr(replay_module, "free_disk_mb", lambda: 999999)
    monkeypatch.setattr(replay_module, "CHUNK_DIR", str(tmp_path))
    monkeypatch.setattr(replay_module._recorder, "chunk_dir", str(tmp_path))
    monkeypatch.setattr(replay_module, "_read_service_cert_password", lambda: "fake-password")
    return events


async def test_start_requires_setup_first(superadmin_client):
    resp = await superadmin_client.post("/api/replay/start")
    assert resp.status_code == 400
    assert "setup" in resp.json()["detail"].lower()


async def test_start_stop_recording_writes_chunk(superadmin_client, mock_container, mock_cot_connection):
    mock_container.set(0, "cert generated")
    await superadmin_client.post("/api/replay/setup")

    resp = await superadmin_client.post("/api/replay/start")
    assert resp.status_code == 200
    chunk_id = resp.json()["chunk_id"]

    status = await superadmin_client.get("/api/replay/status")
    assert status.json()["recording"] is True
    assert status.json()["current_chunk_id"] == chunk_id

    stop_resp = await superadmin_client.post("/api/replay/stop")
    assert stop_resp.status_code == 200

    status = await superadmin_client.get("/api/replay/status")
    assert status.json()["recording"] is False


async def test_start_rejects_when_already_recording(superadmin_client, mock_container, mock_cot_connection):
    mock_container.set(0, "cert generated")
    await superadmin_client.post("/api/replay/setup")

    await superadmin_client.post("/api/replay/start")
    second = await superadmin_client.post("/api/replay/start")
    assert second.status_code == 400
    await superadmin_client.post("/api/replay/stop")


async def test_stop_without_recording_returns_400(superadmin_client):
    resp = await superadmin_client.post("/api/replay/stop")
    assert resp.status_code == 400


async def test_play_chunk_not_found(superadmin_client):
    resp = await superadmin_client.post("/api/replay/chunks/does-not-exist/play", json={"speed": 1})
    assert resp.status_code == 404


async def test_play_rejects_invalid_speed(superadmin_client, session_factory):
    async with session_factory() as session:
        session.add(ReplayChunk(id="chunk-play-1"))
        await session.commit()

    resp = await superadmin_client.post("/api/replay/chunks/chunk-play-1/play", json={"speed": 3})
    assert resp.status_code == 400


async def test_play_chunk_missing_file_returns_404(superadmin_client, session_factory):
    async with session_factory() as session:
        session.add(ReplayChunk(id="chunk-play-2"))
        await session.commit()

    resp = await superadmin_client.post("/api/replay/chunks/chunk-play-2/play", json={"speed": 1})
    assert resp.status_code == 404


async def test_play_chunk_success(superadmin_client, mock_container, mock_cot_connection, session_factory, tmp_path):
    mock_container.set(0, "cert generated")
    await superadmin_client.post("/api/replay/setup")

    chunk_id = "chunk-play-3"
    async with session_factory() as session:
        session.add(ReplayChunk(id=chunk_id))
        await session.commit()
    (tmp_path / f"{chunk_id}.ndjson").write_text(
        '{"ts": 1, "raw_cot": "<event/>"}\n{"ts": 5000, "raw_cot": "<event/>"}\n'
    )

    resp = await superadmin_client.post(f"/api/replay/chunks/{chunk_id}/play", json={"speed": 1})
    assert resp.status_code == 200

    status = await superadmin_client.get("/api/replay/status")
    assert status.json()["playback"] is True

    stop_resp = await superadmin_client.post("/api/replay/stop-playback")
    assert stop_resp.status_code == 200

    status = await superadmin_client.get("/api/replay/status")
    assert status.json()["playback"] is False


async def test_stop_playback_when_not_playing_is_a_noop(superadmin_client):
    resp = await superadmin_client.post("/api/replay/stop-playback")
    assert resp.status_code == 200
    assert resp.json()["status"] == "not_playing"
