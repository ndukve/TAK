import asyncio
import os
import re
import time
import xml.etree.ElementTree as ET

import aiofiles
import httpx
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.responses import FileResponse, Response

from .db import get_db
from .deps import require_role
from .models import ReplaySettings
from .replay import CERT_DIR, SERVER_ADDR, SERVICE_CERT_NAME, ensure_service_cert_authorized
from .replay_recorder import _open_cot_connection

router = APIRouter(prefix="/api/live-map", tags=["live-map"])
_viewer = require_role("admin", "superadmin")
_superadmin = require_role("superadmin")

# OpenStreetMap's tile usage policy (operations.osmfoundation.org/policies/tiles)
# requires a real, identifying User-Agent and forbids heavy direct/uncached use
# from browsers — neither of which a Leaflet <img> tag hitting tile servers
# straight from the client can satisfy (browsers won't let JS set a custom
# User-Agent, and every open tab re-fetches the same tiles). Proxying and
# caching tiles here is what got this deployment 403'd for policy violations
# fixed: we identify ourselves properly and only hit OSM once per tile ever.
#
# Lives under /tmp (the admin_tmp volume), not /opt/tak/data — that directory
# is owned 10000:10000 (takserver's own uid) with no group-write bit, so the
# admin container (uid 10001) can't create new subdirectories there.
TILE_CACHE_DIR = "/tmp/tile-cache"
# TODO: replace with a real contact URL/email per OSM's tile usage policy.
TILE_USER_AGENT = "TAK-Admin-LiveMap/1.0 (self-hosted internal deployment)"

# Optional: matches EFDI's own mainline.inc TERMINAL reference, which uses
# Mapbox's satellite-streets style (satellite imagery with roads/labels
# composited server-side) rather than plain OSM raster. Falls back to plain
# OSM below when unset, so a deployment without a Mapbox token keeps working
# exactly as before.
MAPBOX_ACCESS_TOKEN = os.environ.get("MAPBOX_ACCESS_TOKEN", "").strip()
MAPBOX_STYLE = "mapbox/satellite-streets-v12"

# CoT events older than this (no fresh update) are dropped from the live picture
# rather than left stale on the map.
STALE_AFTER_SECONDS = 300

_EVENT_RE = re.compile(rb"<event\b.*?</event>", re.DOTALL)

_AFFILIATION = {"f": "friendly", "h": "hostile", "n": "neutral", "u": "unknown"}

# EFDI's tak_layer.py embeds a detection's audio clip URL as a plain
# "AUDIO: <url>" line inside <detail><remarks> for dronuradaras acoustic
# sensor tracks (see compose/layers/tak_layer.py in the EFDI repo) — there's
# no dedicated CoT field for it, so pull it back out of the free-text remarks.
_AUDIO_URL_RE = re.compile(r"AUDIO:\s*(\S+)")


def _affiliation(cot_type: str) -> str:
    parts = cot_type.split("-")
    if len(parts) >= 2 and parts[0] == "a":
        return _AFFILIATION.get(parts[1], "unknown")
    return "unknown"


def _parse_events(buffer: bytes) -> tuple[list[dict], bytes]:
    """Extracts complete <event>...</event> documents from a raw CoT byte
    buffer (the TAK CoT stream sends back-to-back XML documents with no
    length prefix). Returns (parsed contacts, unconsumed tail)."""
    contacts = []
    last_end = 0
    for m in _EVENT_RE.finditer(buffer):
        last_end = m.end()
        try:
            root = ET.fromstring(m.group(0))
        except ET.ParseError:
            continue
        point = root.find("point")
        if point is None:
            continue
        try:
            lat = float(point.get("lat", "0"))
            lon = float(point.get("lon", "0"))
        except ValueError:
            continue
        if lat == 0 and lon == 0:
            continue
        contact = root.find("detail/contact")
        track = root.find("detail/track")
        remarks_el = root.find("detail/remarks")
        remarks = remarks_el.text if remarks_el is not None and remarks_el.text else None
        audio_match = _AUDIO_URL_RE.search(remarks) if remarks else None
        image_link = root.find("detail/link[@relation='r-u']")
        contacts.append({
            "uid": root.get("uid", ""),
            "type": root.get("type", ""),
            "affiliation": _affiliation(root.get("type", "")),
            "callsign": contact.get("callsign") if contact is not None else root.get("uid", ""),
            "lat": lat,
            "lon": lon,
            "hae": point.get("hae"),
            "ce": point.get("ce"),
            "le": point.get("le"),
            "speed": track.get("speed") if track is not None else None,
            "course": track.get("course") if track is not None else None,
            "how": root.get("how"),
            "time": root.get("time"),
            "stale": root.get("stale"),
            "remarks": remarks,
            "audio_url": audio_match.group(1) if audio_match else None,
            "image_url": image_link.get("url") if image_link is not None else None,
        })
    return contacts, buffer[last_end:]


class MapTracker:
    """Maintains an in-memory snapshot of the most recent CoT position per
    uid, fed by the same service-cert CoT connection replay recording uses.
    Read-only consumer of the stream — never writes back to the server."""

    def __init__(self, server_addr: str):
        self.server_addr = server_addr
        self._task = None
        self._stop_event = None
        self._reader = None
        self._writer = None
        self._contacts: dict[str, dict] = {}

    def is_tracking(self) -> bool:
        return self._task is not None and not self._task.done()

    def contacts(self) -> list[dict]:
        now = time.time()
        fresh = {}
        for uid, c in self._contacts.items():
            seen_at = c.get("_seen_at", 0)
            if now - seen_at <= STALE_AFTER_SECONDS:
                fresh[uid] = c
        self._contacts = fresh
        return [{k: v for k, v in c.items() if k != "_seen_at"} for c in fresh.values()]

    async def start(self, cert_path: str, key_path: str, key_password: str) -> None:
        if self.is_tracking():
            raise RuntimeError("Already tracking")
        self._stop_event = asyncio.Event()
        self._reader, self._writer = await _open_cot_connection(cert_path, key_path, key_password, self.server_addr)
        self._task = asyncio.ensure_future(self._track_loop())

    async def stop(self) -> None:
        if not self.is_tracking():
            return
        self._stop_event.set()
        if self._writer:
            self._writer.close()
        await self._task
        self._task = None

    async def _track_loop(self) -> None:
        buffer = b""
        while not self._stop_event.is_set():
            try:
                data = await asyncio.wait_for(self._reader.read(65536), timeout=1.0)
            except TimeoutError:
                continue
            if not data:
                break
            buffer += data
            events, buffer = _parse_events(buffer)
            now = time.time()
            for ev in events:
                ev["_seen_at"] = now
                self._contacts[ev["uid"]] = ev


_tracker = MapTracker(SERVER_ADDR)


async def _service_cert_ready(db: AsyncSession) -> bool:
    result = await db.execute(select(ReplaySettings).where(ReplaySettings.id == "singleton"))
    settings = result.scalar_one_or_none()
    return bool(settings and settings.service_cert_ready)


# No auth dependency here, unlike every other route in this file — Leaflet
# requests tiles as plain <img> tags, which can't carry the bearer token this
# app uses everywhere else. Tile imagery itself isn't sensitive; only the
# live contact positions (served above, with auth) are.
@router.get("/tiles/{z}/{x}/{y}.png")
async def get_tile(z: int, x: int, y: int):
    # Namespaced by provider so an operator adding (or removing)
    # MAPBOX_ACCESS_TOKEN later doesn't serve the other provider's stale
    # tiles straight out of the cache.
    provider = "mapbox" if MAPBOX_ACCESS_TOKEN else "osm"
    cache_dir = os.path.join(TILE_CACHE_DIR, provider, str(z), str(x))
    cache_path = os.path.join(cache_dir, f"{y}.tile")
    content_type_path = os.path.join(cache_dir, f"{y}.content-type")
    if os.path.isfile(cache_path):
        try:
            async with aiofiles.open(content_type_path) as f:
                cached_content_type = (await f.read()).strip() or "image/png"
        except OSError:
            cached_content_type = "image/png"
        return FileResponse(cache_path, media_type=cached_content_type)

    os.makedirs(cache_dir, exist_ok=True)
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            if MAPBOX_ACCESS_TOKEN:
                resp = await client.get(
                    f"https://api.mapbox.com/styles/v1/{MAPBOX_STYLE}/tiles/512/{z}/{x}/{y}@2x",
                    params={"access_token": MAPBOX_ACCESS_TOKEN},
                )
            else:
                resp = await client.get(
                    f"https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    headers={"User-Agent": TILE_USER_AGENT},
                )
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=502, detail=f"Tile fetch failed: {exc}") from exc
    if resp.status_code != 200:
        raise HTTPException(status_code=resp.status_code, detail="Tile upstream error")

    content_type = resp.headers.get("content-type", "image/png").split(";", 1)[0].strip() or "image/png"
    async with aiofiles.open(cache_path, "wb") as f:
        await f.write(resp.content)
    async with aiofiles.open(content_type_path, "w") as f:
        await f.write(content_type)
    return Response(content=resp.content, media_type=content_type)


@router.get("/status")
async def get_status(db: AsyncSession = Depends(get_db), _=Depends(_viewer)):
    return {
        "service_cert_ready": await _service_cert_ready(db),
        "tracking": _tracker.is_tracking(),
        "contact_count": len(_tracker.contacts()),
        "mapbox_enabled": bool(MAPBOX_ACCESS_TOKEN),
    }


@router.get("/contacts")
async def get_contacts(_=Depends(_viewer)):
    return {"contacts": _tracker.contacts()}


@router.post("/start")
async def start_tracking(db: AsyncSession = Depends(get_db), _=Depends(_superadmin)):
    if not await _service_cert_ready(db):
        raise HTTPException(status_code=400, detail="Set up the replay service certificate first")
    if _tracker.is_tracking():
        return {"status": "already_tracking"}

    await ensure_service_cert_authorized()
    try:
        with open(f"{CERT_DIR}/{SERVICE_CERT_NAME}.certpass") as f:
            key_password = f.read().strip()
        cert_path = f"{CERT_DIR}/{SERVICE_CERT_NAME}.pem"
        key_path = f"{CERT_DIR}/{SERVICE_CERT_NAME}.key"
        await _tracker.start(cert_path, key_path, key_password)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Unable to connect to the TAK CoT service: {exc}") from exc
    return {"status": "ok"}


@router.post("/stop")
async def stop_tracking(_=Depends(_superadmin)):
    if not _tracker.is_tracking():
        return {"status": "not_tracking"}
    await _tracker.stop()
    return {"status": "ok"}
