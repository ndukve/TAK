import os
import uuid as _uuid_mod
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .deps import require_role, write_audit
from .docker_exec import run_in_container
from .models import ReplayChunk, ReplaySettings
from .replay_recorder import ReplayPlayer, ReplayRecorder, free_disk_mb

router = APIRouter(prefix="/api/replay", tags=["replay"])
_superadmin = require_role("superadmin")

CHUNK_DIR = "/opt/tak/data/replay"
CERT_DIR = "/opt/tak/data/certs/files"
SERVICE_CERT_NAME = "replay-Service"
SERVER_ADDR = "takserver_config"
_VALID_SPEEDS = {1, 2, 5, 10}

_recorder = ReplayRecorder(CHUNK_DIR, SERVER_ADDR)
_player = ReplayPlayer(SERVER_ADDR)


def _read_service_cert_password() -> str:
    with open(os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.certpass")) as f:
        return f.read().strip()


async def _get_or_create_settings(db: AsyncSession) -> ReplaySettings:
    result = await db.execute(select(ReplaySettings).where(ReplaySettings.id == "singleton"))
    settings = result.scalar_one_or_none()
    if settings is None:
        settings = ReplaySettings(id="singleton")
        db.add(settings)
        await db.commit()
        await db.refresh(settings)
    return settings


class ReplaySettingsRequest(BaseModel):
    max_disk_mb: int | None = None
    min_free_disk_mb: int | None = None
    chunk_minutes: int | None = None


@router.get("/status")
async def get_status(db: AsyncSession = Depends(get_db), _=Depends(_superadmin)):
    settings = await _get_or_create_settings(db)
    return {
        "service_cert_ready": settings.service_cert_ready,
        "recording": _recorder.is_recording(),
        "current_chunk_id": _recorder.current_chunk_id(),
        "playback": _player.is_playing(),
        "settings": {
            "max_disk_mb": settings.max_disk_mb,
            "min_free_disk_mb": settings.min_free_disk_mb,
            "chunk_minutes": settings.chunk_minutes,
        },
    }


@router.put("/settings")
async def update_settings(body: ReplaySettingsRequest, db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    settings = await _get_or_create_settings(db)
    if body.max_disk_mb is not None:
        if body.max_disk_mb < 0:
            raise HTTPException(status_code=400, detail="max_disk_mb must be >= 0")
        settings.max_disk_mb = body.max_disk_mb
    if body.min_free_disk_mb is not None:
        if body.min_free_disk_mb < 0:
            raise HTTPException(status_code=400, detail="min_free_disk_mb must be >= 0")
        settings.min_free_disk_mb = body.min_free_disk_mb
    if body.chunk_minutes is not None:
        if body.chunk_minutes < 1:
            raise HTTPException(status_code=400, detail="chunk_minutes must be >= 1")
        settings.chunk_minutes = body.chunk_minutes
    await db.commit()
    await write_audit(db, actor.id, "update_replay_settings")
    return {"status": "ok"}


@router.get("/chunks")
async def list_chunks(db: AsyncSession = Depends(get_db), _=Depends(_superadmin)):
    result = await db.execute(select(ReplayChunk).order_by(ReplayChunk.started_at.desc()))
    chunks = result.scalars().all()
    return {"chunks": [
        {
            "id": c.id,
            "started_at": c.started_at,
            "ended_at": c.ended_at,
            "event_count": c.event_count,
            "size_bytes": c.size_bytes,
        }
        for c in chunks
    ]}


@router.delete("/chunks/{chunk_id}")
async def delete_chunk(chunk_id: str, db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    chunk = await db.get(ReplayChunk, chunk_id)
    if chunk is None:
        raise HTTPException(status_code=404, detail="Chunk not found")
    path = os.path.join(CHUNK_DIR, f"{os.path.basename(chunk_id)}.ndjson")
    if os.path.isfile(path):
        os.remove(path)
    await db.delete(chunk)
    await db.commit()
    await write_audit(db, actor.id, "delete_replay_chunk", chunk_id)
    return {"status": "deleted"}


@router.post("/setup")
async def setup_service_cert(db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    settings = await _get_or_create_settings(db)
    if settings.service_cert_ready:
        return {"status": "already_ready"}

    code, out = await run_in_container(
        ["bash", "/opt/scripts/gen_client_cert.sh"],
        env={"CLIENT_CERT_NAME": SERVICE_CERT_NAME},
    )
    if code != 0:
        raise HTTPException(status_code=502, detail=f"Certificate generation failed: {out}")

    settings.service_cert_ready = True
    await db.commit()
    await write_audit(db, actor.id, "setup_replay_service_cert")
    return {"status": "ok"}


@router.post("/start")
async def start_recording(db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    settings = await _get_or_create_settings(db)
    if not settings.service_cert_ready:
        raise HTTPException(status_code=400, detail="Run setup first")
    if _recorder.is_recording():
        raise HTTPException(status_code=400, detail="Already recording")
    if free_disk_mb() < settings.min_free_disk_mb:
        raise HTTPException(status_code=400, detail="Insufficient free disk space")

    chunk_id = _uuid_mod.uuid4().hex
    cert_path = os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.pem")
    key_path = os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.key")
    key_password = _read_service_cert_password()
    await _recorder.start(chunk_id, cert_path, key_path, key_password)

    chunk = ReplayChunk(id=chunk_id)
    db.add(chunk)
    await db.commit()
    await write_audit(db, actor.id, "start_replay_recording", chunk_id)
    return {"status": "ok", "chunk_id": chunk_id}


@router.post("/stop")
async def stop_recording(db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    if not _recorder.is_recording():
        raise HTTPException(status_code=400, detail="Not recording")
    chunk_id = _recorder.current_chunk_id()
    event_count, size_bytes = await _recorder.stop()

    chunk = await db.get(ReplayChunk, chunk_id)
    if chunk:
        chunk.event_count = event_count
        chunk.size_bytes = size_bytes
        chunk.ended_at = datetime.now(UTC)
        await db.commit()
    await write_audit(db, actor.id, "stop_replay_recording", chunk_id)
    return {"status": "ok", "chunk_id": chunk_id, "event_count": event_count}


class PlayRequest(BaseModel):
    speed: int = 1


@router.post("/chunks/{chunk_id}/play")
async def play_chunk(chunk_id: str, body: PlayRequest, db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    if body.speed not in _VALID_SPEEDS:
        raise HTTPException(status_code=400, detail=f"speed must be one of {sorted(_VALID_SPEEDS)}")
    chunk = await db.get(ReplayChunk, chunk_id)
    if chunk is None:
        raise HTTPException(status_code=404, detail="Chunk not found")

    chunk_path = os.path.join(CHUNK_DIR, f"{os.path.basename(chunk_id)}.ndjson")
    if not os.path.isfile(chunk_path):
        raise HTTPException(status_code=404, detail="Chunk file missing from disk")

    if _player.is_playing():
        await _player.stop()

    key_password = _read_service_cert_password()
    cert_path = os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.pem")
    key_path = os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.key")
    await _player.start(chunk_path, body.speed, cert_path, key_path, key_password)

    await write_audit(db, actor.id, "start_replay_playback", f"{chunk_id} @ {body.speed}x")
    return {"status": "ok", "chunk_id": chunk_id, "speed": body.speed}


@router.post("/stop-playback")
async def stop_playback(db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    if not _player.is_playing():
        return {"status": "not_playing"}
    await _player.stop()
    await write_audit(db, actor.id, "stop_replay_playback")
    return {"status": "ok"}
