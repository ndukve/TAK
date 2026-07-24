import asyncio
import hashlib
import hmac
import io
import ipaddress
import json
import math
import os
import re
import socket
import sqlite3
import ssl
import time
import uuid
import xml.etree.ElementTree as ET
import zipfile
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from urllib.parse import parse_qsl, quote, urlencode, urlsplit, urlunsplit
from xml.sax.saxutils import escape

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from . import packages
from .db import get_db
from .deps import SECRET_KEY, require_role, write_audit
from .docker_exec import run_in_container
from .models import BasemapDistribution
from .replay import CERT_DIR, TAK_USER_GROUP

router = APIRouter(prefix="/api/basemaps", tags=["basemaps"])
_superadmin = require_role("superadmin")

MAX_XML_BYTES = 1024 * 1024
MISSION_PREFIX = "TAK-Basemaps"
SERVICE_CERT_NAME = os.environ.get("BASEMAP_SERVICE_CERT_NAME", "basemap-Service")
TAK_API_ADDRESS = os.environ.get("TAK_API_ADDRESS", "takserver")
TAK_SERVER_ADDRESS = os.environ.get("TAK_SERVER_ADDRESS", "localhost")
TILE_PROXY_URL = os.environ.get("TAK_BASEMAP_PROXY_URL") or f"https://{TAK_SERVER_ADDRESS}:8889"
TILE_PROXY_ENABLED = os.environ.get("TAK_BASEMAP_PROXY_ENABLED", "1") == "1"
TILE_CACHE_DIR = os.environ.get("TAK_BASEMAP_CACHE_DIR", "/opt/tak/data/basemap-cache")
TILE_CACHE_MAX_BYTES = int(os.environ.get("TAK_BASEMAP_CACHE_MAX_MB", "2048")) * 1024 * 1024
MAX_OFFLINE_PUSH_BYTES = int(os.environ.get("TAK_BASEMAP_OFFLINE_PUSH_MAX_MB", "512")) * 1024 * 1024
MAX_AOI_TILES = int(os.environ.get("TAK_BASEMAP_AOI_MAX_TILES", "5000"))
CREATOR_UID = SERVICE_CERT_NAME
WEATHER_SOURCE_IDS = {"rainviewer-radar", "noaa-radar", "nasa-imerg", "goes-west", "goes-east"}
_tile_locks: dict[str, asyncio.Lock] = {}


def _tile_source(
    name: str,
    url: str,
    *,
    description: str,
    tile_type: str = "png",
    min_zoom: int = 0,
    max_zoom: int = 19,
) -> dict:
    return {
        "name": name,
        "description": description,
        "type": "MapTile",
        "url": url,
        "tileType": tile_type,
        "minZoom": min_zoom,
        "maxZoom": max_zoom,
    }


def _wms_source(name: str, layer: str, *, description: str, max_zoom: int = 12) -> dict:
    return {
        "name": name,
        "description": description,
        "type": "WMS",
        "url": "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?",
        "tileType": "png",
        "minZoom": 0,
        "maxZoom": max_zoom,
        "version": "1.3.0",
        "coordinateSystem": "EPSG:4326",
        "layers": layer,
        "additionalParameters": "&TRANSPARENT=TRUE",
    }


BUILTIN_SOURCES = {
    "esri-street": _tile_source(
        "ESRI - World Street Map",
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{$z}/{$y}/{$x}",
        description="ESRI global street basemap.",
        tile_type="jpg",
        max_zoom=20,
    ),
    "esri-imagery": _tile_source(
        "ESRI - World Imagery",
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{$z}/{$y}/{$x}",
        description="ESRI global satellite and aerial imagery.",
        tile_type="jpg",
        max_zoom=20,
    ),
    "esri-clarity": _tile_source(
        "ESRI - Clarity",
        "https://clarity.maptiles.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/tile/{$z}/{$y}/{$x}",
        description="ESRI archived clarity imagery.",
        tile_type="jpg",
        max_zoom=20,
    ),
    "esri-topo": _tile_source(
        "ESRI - World Topo",
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{$z}/{$y}/{$x}",
        description="ESRI global topographic basemap.",
        tile_type="jpg",
        max_zoom=20,
    ),
    "google-satellite": _tile_source(
        "Google - Satellite",
        "https://mt1.google.com/vt/lyrs=s&x={$x}&y={$y}&z={$z}",
        description="Google satellite imagery.",
        tile_type="jpg",
        max_zoom=20,
    ),
    "google-roadmap": _tile_source(
        "Google - Roadmap Standard",
        "https://mt1.google.com/vt/lyrs=m&x={$x}&y={$y}&z={$z}",
        description="Google standard road map.",
        tile_type="jpg",
        max_zoom=20,
    ),
    "google-terrain": _tile_source(
        "Google - Terrain",
        "https://mt1.google.com/vt/lyrs=p&x={$x}&y={$y}&z={$z}",
        description="Google terrain basemap.",
        tile_type="jpg",
        max_zoom=20,
    ),
    "noaa-radar": {
        "name": "NOAA - CONUS Radar",
        "description": "Near-live NOAA/NCEP composite base reflectivity for the continental United States.",
        "type": "WMS",
        "url": "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows?",
        "tileType": "png",
        "minZoom": 3,
        "maxZoom": 12,
        "version": "1.3.0",
        "coordinateSystem": "EPSG:3857",
        "layers": "conus_bref_qcd",
        "additionalParameters": "&TRANSPARENT=TRUE",
        "north": 55.0,
        "south": 20.0,
        "east": -60.0,
        "west": -130.0,
        "opacity": 70,
    },
    "rainviewer-radar": {
        "name": "RainViewer - Global Radar",
        "description": "Latest available global precipitation radar frame from RainViewer.",
        "type": "DYNAMIC_RAINVIEWER",
        "opacity": 70,
    },
    "nasa-imerg": _wms_source(
        "NASA - IMERG Precipitation",
        "IMERG_Precipitation_Rate",
        description="NASA GIBS global satellite-estimated precipitation rate.",
        max_zoom=10,
    ),
    "goes-west": _wms_source(
        "NOAA/NASA - GOES-18 Pacific GeoColor",
        "GOES-West_ABI_GeoColor",
        description="Near-live GOES-18 Pacific daytime true color and nighttime multispectral imagery.",
        max_zoom=8,
    ),
    "goes-east": _wms_source(
        "NOAA/NASA - GOES-19 Atlantic GeoColor",
        "GOES-East_ABI_GeoColor",
        description="Near-live GOES-19 Atlantic daytime true color and nighttime multispectral imagery.",
        max_zoom=8,
    ),
}

PRESETS = (
    ("esri-noaa-radar", "ESRI + NOAA Radar", "Near-live CONUS radar with ESRI Street and Imagery.", ("esri-street", "esri-imagery", "noaa-radar")),
    ("esri-rainviewer", "ESRI + RainViewer", "Latest global radar frame with ESRI Street and Imagery.", ("esri-street", "esri-imagery", "rainviewer-radar")),
    ("esri-nasa-imerg", "ESRI + NASA IMERG", "Global satellite-estimated precipitation with ESRI Street and Imagery.", ("esri-street", "esri-imagery", "nasa-imerg")),
    ("esri-goes-west", "ESRI + GOES-18 Pacific", "Near-live GOES-18 Pacific GeoColor with ESRI Street and Imagery.", ("esri-street", "esri-imagery", "goes-west")),
    ("esri-goes-east", "ESRI + GOES-19 Atlantic", "Near-live GOES-19 Atlantic GeoColor with ESRI Street and Imagery.", ("esri-street", "esri-imagery", "goes-east")),
    ("esri-clarity", "ESRI: Clarity", "ESRI archived clarity imagery.", ("esri-clarity",)),
    ("esri-world-topo", "ESRI: World Topo", "ESRI global topographic basemap.", ("esri-topo",)),
    ("google-satellite", "Google: Satellite", "Google satellite imagery.", ("google-satellite",)),
    ("google-roadmap", "Google: Roadmap Standard", "Google standard road map.", ("google-roadmap",)),
    ("google-terrain", "Google: Terrain", "Google terrain basemap.", ("google-terrain",)),
)
PRESET_BY_ID = {preset[0]: preset for preset in PRESETS}


class CustomUrlRequest(BaseModel):
    name: str
    url: str


class PushRequest(BaseModel):
    item_ids: list[str]
    recipient_uids: list[str]
    overlay_opacity: int = Field(default=70, ge=0, le=100)
    request_id: str | None = Field(default=None, min_length=8, max_length=64)


class CleanupRequest(BaseModel):
    older_than_days: int = Field(default=30, ge=1, le=3650)


class OfflineBuildRequest(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    source_id: str
    west: float = Field(ge=-180, le=180)
    south: float = Field(ge=-85, le=85)
    east: float = Field(ge=-180, le=180)
    north: float = Field(ge=-85, le=85)
    min_zoom: int = Field(ge=0, le=20)
    max_zoom: int = Field(ge=0, le=20)


def _text(root: ET.Element, name: str, default: str = "") -> str:
    node = root.find(name)
    return (node.text or "").strip() if node is not None else default


def _parse_bool(value: str, default: bool = False) -> bool:
    if not value:
        return default
    return value.lower() == "true"


def parse_map_source(xml_data: bytes, *, fallback_name: str = "Custom map source") -> dict:
    if not xml_data or len(xml_data) > MAX_XML_BYTES:
        raise ValueError("XML map source must be between 1 byte and 1 MB")
    upper = xml_data.upper()
    if b"<!DOCTYPE" in upper or b"<!ENTITY" in upper:
        raise ValueError("DTD and entity declarations are not allowed")
    try:
        root = ET.fromstring(xml_data)
    except ET.ParseError as exc:
        raise ValueError(f"Invalid XML: {exc}") from exc
    if root.tag not in {"customMapSource", "customWmsMapSource"}:
        raise ValueError("Expected customMapSource or customWmsMapSource XML")

    source_url = _text(root, "url")
    parsed_url = urlsplit(source_url)
    if parsed_url.scheme not in {"http", "https"} or not parsed_url.hostname:
        raise ValueError("Map source URL must be HTTP or HTTPS")
    try:
        min_zoom = int(_text(root, "minZoom", "0"))
        max_zoom = int(_text(root, "maxZoom", "19"))
        north = float(_text(root, "north", "85"))
        south = float(_text(root, "south", "-85"))
        east = float(_text(root, "east", "180"))
        west = float(_text(root, "west", "-180"))
        opacity = int(_text(root, "opacity", "100"))
    except ValueError as exc:
        raise ValueError("Zoom, bounds, or opacity contains an invalid number") from exc
    if not 0 <= min_zoom <= max_zoom <= 30:
        raise ValueError("Zoom range must be between 0 and 30")
    if not (-85 <= south < north <= 85 and -180 <= west < east <= 180):
        raise ValueError("Map bounds are invalid")
    if not 0 <= opacity <= 100:
        raise ValueError("Opacity must be between 0 and 100")

    is_wms = root.tag == "customWmsMapSource"
    return {
        "name": _text(root, "name", fallback_name)[:120],
        "description": "Custom ATAK XML map source.",
        "type": "WMS" if is_wms else "MapTile",
        "url": source_url,
        "tileType": _text(root, "tileType", "png").lower(),
        "minZoom": min_zoom,
        "maxZoom": max_zoom,
        "version": _text(root, "version", "1.3.0" if is_wms else ""),
        "coordinateSystem": _text(root, "coordinatesystem", _text(root, "coordinateSystem")),
        "layers": _text(root, "layers"),
        "additionalParameters": _text(root, "aditionalparameters", _text(root, "additionalParameters")),
        "serverParts": _text(root, "serverParts"),
        "backgroundColor": _text(root, "backgroundColor", "#000000"),
        "tileUpdate": _text(root, "tileUpdate", "None"),
        "ignoreErrors": _parse_bool(_text(root, "ignoreErrors")),
        "invertYCoordinate": _parse_bool(_text(root, "invertYCoordinate")),
        "north": north,
        "south": south,
        "east": east,
        "west": west,
        "opacity": opacity,
    }


def _library_sources() -> list[dict]:
    result = []
    if not os.path.isdir(packages.MAPS_DIR):
        return result
    for provider in sorted(os.listdir(packages.MAPS_DIR)):
        provider_dir = os.path.join(packages.MAPS_DIR, provider)
        if not os.path.isdir(provider_dir):
            continue
        for filename in sorted(name for name in os.listdir(provider_dir) if name.endswith((".xml", ".mbtiles"))):
            path = os.path.join(provider_dir, filename)
            if filename.endswith(".mbtiles"):
                try:
                    size_bytes = os.path.getsize(path)
                except OSError:
                    continue
                result.append(
                    {
                        "id": f"offline:{provider}/{filename}",
                        "name": filename.removesuffix(".mbtiles"),
                        "description": f"Offline MBTiles package from {provider}.",
                        "provider": provider,
                        "kind": "offline",
                        "size_bytes": size_bytes,
                    }
                )
                continue
            try:
                with open(path, "rb") as source_file:
                    layer = parse_map_source(source_file.read(MAX_XML_BYTES + 1), fallback_name=filename.removesuffix(".xml"))
            except (OSError, ValueError):
                continue
            result.append({
                "id": f"library:{provider}/{filename}",
                "name": layer["name"],
                "description": f"Stored map source from {provider}.",
                "provider": provider,
                "kind": "xml",
            })
    return result


def _load_library_source(source_id: str) -> dict:
    relative = source_id.removeprefix("library:")
    if "/" not in relative:
        raise HTTPException(status_code=400, detail=f"Invalid map source: {source_id}")
    provider, filename = relative.split("/", 1)
    if os.path.basename(provider) != provider or os.path.basename(filename) != filename or not filename.endswith(".xml"):
        raise HTTPException(status_code=400, detail=f"Invalid map source: {source_id}")
    path = os.path.join(packages.MAPS_DIR, provider, filename)
    if not os.path.realpath(path).startswith(os.path.realpath(packages.MAPS_DIR) + os.sep):
        raise HTTPException(status_code=400, detail=f"Invalid map source: {source_id}")
    try:
        with open(path, "rb") as source_file:
            return parse_map_source(source_file.read(MAX_XML_BYTES + 1), fallback_name=filename.removesuffix(".xml"))
    except OSError as exc:
        raise HTTPException(status_code=404, detail=f"Map source not found: {source_id}") from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid map source {source_id}: {exc}") from exc


def _load_offline_source(source_id: str) -> str:
    relative = source_id.removeprefix("offline:")
    if "/" not in relative:
        raise HTTPException(status_code=400, detail=f"Invalid offline map: {source_id}")
    provider, filename = relative.split("/", 1)
    if os.path.basename(provider) != provider or os.path.basename(filename) != filename or not filename.endswith(".mbtiles"):
        raise HTTPException(status_code=400, detail=f"Invalid offline map: {source_id}")
    path = os.path.join(packages.MAPS_DIR, provider, filename)
    if not os.path.realpath(path).startswith(os.path.realpath(packages.MAPS_DIR) + os.sep):
        raise HTTPException(status_code=400, detail=f"Invalid offline map: {source_id}")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail=f"Offline map not found: {source_id}")
    if os.path.getsize(path) > MAX_OFFLINE_PUSH_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"Offline mission packages are limited to {MAX_OFFLINE_PUSH_BYTES // (1024 * 1024)} MB",
        )
    return path


def _managed_source_path(provider: str, filename: str) -> str:
    allowed_suffix = ".xml" if provider == "Custom" else ".mbtiles" if provider == "Offline" else ""
    if (
        not allowed_suffix
        or os.path.basename(filename) != filename
        or not filename.endswith(allowed_suffix)
    ):
        raise HTTPException(status_code=400, detail="Only custom XML and generated offline sources can be deleted")
    path = os.path.join(packages.MAPS_DIR, provider, filename)
    if not os.path.realpath(path).startswith(os.path.realpath(packages.MAPS_DIR) + os.sep):
        raise HTTPException(status_code=400, detail="Invalid map source path")
    return path


async def _resolve_rainviewer() -> dict:
    try:
        async with httpx.AsyncClient(timeout=10, follow_redirects=False) as client:
            response = await client.get("https://api.rainviewer.com/public/weather-maps.json")
            response.raise_for_status()
            data = response.json()
        frames = data.get("radar", {}).get("past", [])
        if not frames:
            raise ValueError("RainViewer returned no radar frames")
        host = data["host"].rstrip("/")
        path = frames[-1]["path"]
    except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=f"Unable to resolve the latest RainViewer radar frame: {exc}") from exc
    return _tile_source(
        "RainViewer - Global Radar",
        f"{host}{path}/256/{{$z}}/{{$x}}/{{$y}}/2/1_1.png",
        description="Latest available global precipitation radar frame from RainViewer.",
        max_zoom=12,
    )


async def _resolve_direct_source(source_id: str) -> dict:
    if source_id.startswith("library:"):
        return _load_library_source(source_id)
    source = BUILTIN_SOURCES.get(source_id)
    if source is None:
        raise HTTPException(status_code=400, detail=f"Unknown basemap source: {source_id}")
    if source.get("type") == "DYNAMIC_RAINVIEWER":
        return await _resolve_rainviewer()
    return dict(source)


def _proxy_token(source_id: str) -> str:
    return hmac.new(SECRET_KEY.encode(), source_id.encode(), hashlib.sha256).hexdigest()[:32]


def _proxy_configuration() -> dict:
    parsed = urlsplit(TILE_PROXY_URL)
    hostname = (parsed.hostname or "").lower()
    warning = None
    if not TILE_PROXY_ENABLED:
        warning = "The TAK tile proxy is disabled; connected devices must reach every upstream source directly."
    elif parsed.scheme != "https" or not hostname:
        warning = "TAK_BASEMAP_PROXY_URL must be a valid public HTTPS URL."
    elif hostname in {"localhost", "0.0.0.0", "127.0.0.1", "::1"}:
        warning = "The tile proxy points to localhost and will not load on another device; set TAK_SERVER_ADDRESS to the EUD-reachable server IP or hostname."
    return {
        "enabled": TILE_PROXY_ENABLED,
        "public_url": TILE_PROXY_URL,
        "cache_max_mb": TILE_CACHE_MAX_BYTES // (1024 * 1024),
        "ready": warning is None,
        "warning": warning,
    }


def _proxy_map_source(source_id: str, source: dict) -> dict:
    proxied = dict(source)
    proxied.update({
        "type": "MapTile",
        "url": f"{TILE_PROXY_URL.rstrip('/')}/api/basemaps/tiles/{_proxy_token(source_id)}/{source_id}/{{$z}}/{{$x}}/{{$y}}",
        "tileType": "png" if source.get("type") == "WMS" or source_id in WEATHER_SOURCE_IDS else source.get("tileType", "png"),
        "serverParts": "",
        "additionalParameters": "",
        "coordinateSystem": "",
        "version": "",
        "layers": "",
    })
    return proxied


async def _resolve_source(source_id: str) -> dict:
    source = await _resolve_direct_source(source_id)
    if TILE_PROXY_ENABLED and source_id in BUILTIN_SOURCES:
        return _proxy_map_source(source_id, source)
    return source


def _tile_lon(x: int, zoom: int) -> float:
    return x / (2**zoom) * 360.0 - 180.0


def _tile_lat(y: int, zoom: int) -> float:
    value = math.pi - (2.0 * math.pi * y) / (2**zoom)
    return math.degrees(math.atan(math.sinh(value)))


def _wms_tile_url(source: dict, zoom: int, x: int, y: int) -> str:
    west, east = _tile_lon(x, zoom), _tile_lon(x + 1, zoom)
    north, south = _tile_lat(y, zoom), _tile_lat(y + 1, zoom)
    coordinate_system = source.get("coordinateSystem") or "EPSG:3857"
    version = source.get("version") or "1.3.0"
    if coordinate_system.upper() == "EPSG:4326":
        bbox = f"{south},{west},{north},{east}" if version == "1.3.0" else f"{west},{south},{east},{north}"
    else:
        limit = 20037508.342789244
        scale = (limit * 2) / (2**zoom)
        min_x = -limit + x * scale
        max_x = min_x + scale
        max_y = limit - y * scale
        min_y = max_y - scale
        bbox = f"{min_x},{min_y},{max_x},{max_y}"
    split = urlsplit(source["url"])
    params = dict(parse_qsl(split.query, keep_blank_values=True))
    params.update(dict(parse_qsl(source.get("additionalParameters", "").lstrip("&"), keep_blank_values=True)))
    params.update({
        "service": "WMS",
        "request": "GetMap",
        "version": version,
        "layers": source.get("layers", ""),
        "styles": "",
        "format": "image/png",
        "transparent": "true",
        "width": "256",
        "height": "256",
        "bbox": bbox,
        "crs" if version == "1.3.0" else "srs": coordinate_system,
    })
    return urlunsplit((split.scheme, split.netloc, split.path, urlencode(params), ""))


async def _upstream_tile_url(source_id: str, zoom: int, x: int, y: int) -> tuple[str, str]:
    source = await _resolve_direct_source(source_id)
    if source.get("type") == "WMS":
        return _wms_tile_url(source, zoom, x, y), "image/png"
    url = source["url"].replace("{$z}", str(zoom)).replace("{$x}", str(x)).replace("{$y}", str(y))
    tile_type = source.get("tileType", "png").lower()
    return url, "image/jpeg" if tile_type in {"jpg", "jpeg"} else "image/png"


def _tile_cache_path(source_id: str, zoom: int, x: int, y: int) -> str:
    return os.path.join(TILE_CACHE_DIR, source_id, str(zoom), str(x), f"{y}.tile")


def _prune_tile_cache() -> None:
    files = []
    total = 0
    if not os.path.isdir(TILE_CACHE_DIR):
        return
    for root, _, names in os.walk(TILE_CACHE_DIR):
        for name in names:
            path = os.path.join(root, name)
            try:
                stat = os.stat(path)
            except OSError:
                continue
            files.append((stat.st_mtime, stat.st_size, path))
            total += stat.st_size
    for _, size, path in sorted(files):
        if total <= TILE_CACHE_MAX_BYTES:
            break
        try:
            os.remove(path)
            total -= size
        except OSError:
            continue


async def _cached_tile(source_id: str, zoom: int, x: int, y: int) -> tuple[bytes, str, int]:
    if source_id not in BUILTIN_SOURCES:
        raise HTTPException(status_code=404, detail="Unknown tile source")
    if not 0 <= zoom <= 22 or not 0 <= x < 2**zoom or not 0 <= y < 2**zoom:
        raise HTTPException(status_code=400, detail="Invalid tile coordinate")
    cache_path = _tile_cache_path(source_id, zoom, x, y)
    ttl = 300 if source_id in WEATHER_SOURCE_IDS else 7 * 24 * 3600
    configured_type = BUILTIN_SOURCES[source_id].get("tileType", "png").lower()
    cached_content_type = "image/jpeg" if configured_type in {"jpg", "jpeg"} else "image/png"
    lock = _tile_locks.setdefault(cache_path, asyncio.Lock())
    async with lock:
        stale_content = None
        try:
            age = time.time() - os.path.getmtime(cache_path)
            with open(cache_path, "rb") as cached:
                stale_content = cached.read()
            if age <= ttl:
                return stale_content, cached_content_type, ttl
        except OSError:
            pass

        try:
            url, expected_type = await _upstream_tile_url(source_id, zoom, x, y)
            async with httpx.AsyncClient(timeout=20, follow_redirects=False) as client:
                upstream = await client.get(url, headers={"Accept": "image/png,image/jpeg"})
                upstream.raise_for_status()
        except (HTTPException, httpx.HTTPError) as exc:
            if stale_content:
                return stale_content, cached_content_type, 60
            if isinstance(exc, HTTPException):
                raise
            raise HTTPException(status_code=502, detail=f"Upstream tile request failed: {exc}") from exc
        content_type = upstream.headers.get("content-type", expected_type).split(";", 1)[0].lower()
        if content_type not in {"image/png", "image/jpeg"} or not upstream.content or len(upstream.content) > 5 * 1024 * 1024:
            if stale_content:
                return stale_content, cached_content_type, 60
            raise HTTPException(status_code=502, detail="Upstream returned an invalid tile")
        temp_path = f"{cache_path}.{uuid.uuid4().hex}.tmp"
        try:
            os.makedirs(os.path.dirname(cache_path), exist_ok=True)
            with open(temp_path, "wb") as output:
                output.write(upstream.content)
            os.replace(temp_path, cache_path)
            await asyncio.to_thread(_prune_tile_cache)
        except OSError:
            try:
                os.remove(temp_path)
            except OSError:
                pass
        return upstream.content, content_type, ttl


def _longitude_tile(longitude: float, zoom: int) -> int:
    return min(2**zoom - 1, max(0, int((longitude + 180.0) / 360.0 * 2**zoom)))


def _latitude_tile(latitude: float, zoom: int) -> int:
    latitude = min(85.05112878, max(-85.05112878, latitude))
    radians = math.radians(latitude)
    value = (1.0 - math.asinh(math.tan(radians)) / math.pi) / 2.0 * 2**zoom
    return min(2**zoom - 1, max(0, int(value)))


def _aoi_coordinates(body: OfflineBuildRequest) -> list[tuple[int, int, int]]:
    if body.west >= body.east or body.south >= body.north or body.min_zoom > body.max_zoom:
        raise HTTPException(status_code=400, detail="Invalid AOI bounds or zoom range")
    coordinates = []
    for zoom in range(body.min_zoom, body.max_zoom + 1):
        min_x = _longitude_tile(body.west, zoom)
        max_x = _longitude_tile(body.east, zoom)
        min_y = _latitude_tile(body.north, zoom)
        max_y = _latitude_tile(body.south, zoom)
        for x in range(min_x, max_x + 1):
            for y in range(min_y, max_y + 1):
                coordinates.append((zoom, x, y))
                if len(coordinates) > MAX_AOI_TILES:
                    raise HTTPException(
                        status_code=413,
                        detail=f"AOI exceeds the {MAX_AOI_TILES}-tile build limit; reduce bounds or zoom",
                    )
    return coordinates


async def _build_offline_mbtiles(body: OfflineBuildRequest) -> dict:
    if body.source_id not in BUILTIN_SOURCES:
        raise HTTPException(status_code=400, detail="Offline AOIs can only use built-in sources")
    display_name, filename = _safe_custom_name(body.name)
    filename = filename.removesuffix(".xml") + ".mbtiles"
    coordinates = _aoi_coordinates(body)
    target_dir = os.path.join(packages.MAPS_DIR, "Offline")
    os.makedirs(target_dir, exist_ok=True)
    target = os.path.join(target_dir, filename)
    temporary = f"{target}.{uuid.uuid4().hex}.building"
    connection = sqlite3.connect(temporary)
    try:
        connection.executescript(
            "CREATE TABLE metadata (name TEXT, value TEXT);"
            "CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);"
            "CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);"
        )
        metadata = {
            "name": display_name,
            "type": "baselayer",
            "version": "1.0",
            "description": f"Offline AOI generated from {body.source_id}",
            "format": "png",
            "bounds": f"{body.west},{body.south},{body.east},{body.north}",
            "minzoom": str(body.min_zoom),
            "maxzoom": str(body.max_zoom),
        }
        connection.executemany("INSERT INTO metadata(name, value) VALUES (?, ?)", metadata.items())
        for start in range(0, len(coordinates), 32):
            batch = coordinates[start:start + 32]
            tiles = await asyncio.gather(*(_cached_tile(body.source_id, zoom, x, y) for zoom, x, y in batch))
            rows = []
            for (zoom, x, y), (content, content_type, _) in zip(batch, tiles, strict=True):
                metadata["format"] = "jpg" if content_type == "image/jpeg" else "png"
                rows.append((zoom, x, 2**zoom - 1 - y, content))
            connection.executemany(
                "INSERT INTO tiles(zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)",
                rows,
            )
            connection.commit()
        connection.execute("UPDATE metadata SET value = ? WHERE name = 'format'", (metadata["format"],))
        connection.commit()
    except Exception:
        connection.close()
        try:
            os.remove(temporary)
        except OSError:
            pass
        raise
    connection.close()
    os.replace(temporary, target)
    return {
        "id": f"offline:Offline/{filename}",
        "name": display_name,
        "filename": filename,
        "tile_count": len(coordinates),
        "size_bytes": os.path.getsize(target),
    }


def _expand_item_ids(item_ids: list[str]) -> list[str]:
    if not item_ids or len(item_ids) > 20:
        raise HTTPException(status_code=400, detail="Select between 1 and 20 basemap entries")
    source_ids = []
    for item_id in item_ids:
        if item_id in PRESET_BY_ID:
            source_ids.extend(PRESET_BY_ID[item_id][3])
        elif item_id.startswith(("library:", "offline:")):
            source_ids.append(item_id)
        else:
            raise HTTPException(status_code=400, detail=f"Unknown basemap entry: {item_id}")
    return list(dict.fromkeys(source_ids))


def _mission_layer(
    source: dict,
    *,
    source_id: str,
    push_id: str,
    after: str = "",
    overlay_opacity: int = 70,
) -> dict:
    is_overlay = source.get("type") == "WMS" or source_id in {"rainviewer-radar", "noaa-radar", "nasa-imerg", "goes-west", "goes-east"}
    return {
        "minZoom": source.get("minZoom", 0),
        "maxZoom": source.get("maxZoom", 19),
        "north": source.get("north", 85.0),
        "south": source.get("south", -85.0),
        "east": source.get("east", 180.0),
        "west": source.get("west", -180.0),
        "uid": f"{push_id}-{re.sub(r'[^a-zA-Z0-9_-]', '-', source_id)[:80]}",
        "creatorUid": CREATOR_UID,
        "name": source["name"],
        "description": source.get("description", ""),
        "type": source.get("type", "MapTile"),
        "url": source["url"],
        "tileType": source.get("tileType", "png"),
        "serverParts": source.get("serverParts", ""),
        "backgroundColor": source.get("backgroundColor", "#000000"),
        "tileUpdate": source.get("tileUpdate", "None"),
        "additionalParameters": source.get("additionalParameters", ""),
        "coordinateSystem": source.get("coordinateSystem", ""),
        "version": source.get("version", ""),
        "layers": source.get("layers", ""),
        "path": "",
        "after": after,
        "opacity": overlay_opacity if is_overlay else source.get("opacity", 100),
        "defaultLayer": False,
        "enabled": True,
        "ignoreErrors": source.get("ignoreErrors", False),
        "invertYCoordinate": source.get("invertYCoordinate", False),
    }


def _tak_ssl_context() -> ssl.SSLContext:
    context = ssl.create_default_context(cafile=os.path.join(CERT_DIR, "root-ca.pem"))
    context.check_hostname = True
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    return context


@asynccontextmanager
async def _tak_client():
    cert_path = os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.pem")
    key_path = os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.key")
    try:
        with open(os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.certpass")) as password_file:
            password = password_file.read().strip()
    except OSError as exc:
        raise HTTPException(status_code=400, detail="Set up the service certificate before using TAK distribution") from exc

    async with httpx.AsyncClient(
        base_url=f"https://{TAK_API_ADDRESS}:8443",
        verify=_tak_ssl_context(),
        cert=(cert_path, key_path, password),
        timeout=30,
        follow_redirects=False,
    ) as client:
        yield client


async def ensure_service_cert_authorized() -> None:
    cert_path = os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.pem")
    if not os.path.isfile(cert_path):
        code, output = await run_in_container(
            ["bash", "/opt/scripts/gen_client_cert.sh"],
            env={"CLIENT_CERT_NAME": SERVICE_CERT_NAME},
        )
        if code != 0:
            raise HTTPException(status_code=502, detail=f"Basemap certificate generation failed: {output}")
    code, output = await run_in_container(
        ["bash", "/opt/scripts/enable_user.sh"],
        env={"USER_CERT_NAME": SERVICE_CERT_NAME, "TAK_USER_GROUP": TAK_USER_GROUP},
    )
    if code != 0:
        raise HTTPException(status_code=502, detail=f"Basemap certificate authorization failed: {output}")


def _connected_client_rows(payload) -> list[dict]:
    if isinstance(payload, list):
        return [row for row in payload if isinstance(row, dict)]
    if not isinstance(payload, dict):
        return []
    if any(key in payload for key in ("clientUid", "uid", "clientEndpointUid")):
        return [payload]
    for key in ("data", "clientEndPoints", "clientEndpoints", "clients"):
        rows = _connected_client_rows(payload.get(key))
        if rows:
            return rows
    return []


async def get_connected_euds() -> list[dict]:
    try:
        async with _tak_client() as client:
            response = await client.get(
                "/Marti/api/clientEndPoints",
                params={"showCurrentlyConnectedClients": "true", "showMostRecentOnly": "true"},
                headers={"Accept": "application/json"},
            )
            response.raise_for_status()
            rows = _connected_client_rows(response.json())
    except (httpx.HTTPError, OSError, ssl.SSLError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=f"Unable to list connected TAK clients: {exc}") from exc

    recipients = {}
    for row in rows:
        uid = row.get("clientUid") or row.get("uid") or row.get("clientEndpointUid")
        if not isinstance(uid, str) or not uid.strip():
            continue
        uid = uid.strip()
        callsign = row.get("callsign") or row.get("name") or row.get("username") or uid
        group = row.get("group") or row.get("team") or "Ungrouped"
        if isinstance(group, list):
            group = group[0] if group else "Ungrouped"
        recipients[uid] = {"uid": uid, "callsign": str(callsign), "group": str(group)}
    return sorted(recipients.values(), key=lambda recipient: (recipient["callsign"].lower(), recipient["uid"]))


def _offline_mission_package(mission_name: str, offline_files: list[str]) -> bytes:
    total_size = sum(os.path.getsize(path) for path in offline_files)
    if total_size > MAX_OFFLINE_PUSH_BYTES:
        raise HTTPException(status_code=413, detail="Combined offline package is too large")
    names = [os.path.basename(path) for path in offline_files]
    if len(names) != len(set(names)):
        raise HTTPException(status_code=400, detail="Offline maps in one push must have unique filenames")
    contents = "".join(
        f'<Content ignore="false" zipEntry="content/{escape(name)}"/>' for name in names
    )
    manifest = (
        '<MissionPackageManifest version="2"><Configuration>'
        f'<Parameter name="uid" value="{escape(mission_name)}-offline"/>'
        f'<Parameter name="name" value="{escape(mission_name)} offline maps"/>'
        '<Parameter name="onReceiveDelete" value="false"/>'
        f"</Configuration><Contents>{contents}</Contents></MissionPackageManifest>"
    )
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("MANIFEST/manifest.xml", manifest)
        for path, name in zip(offline_files, names, strict=True):
            archive.write(path, f"content/{name}")
    return output.getvalue()


async def publish_basemap_mission(
    layers: list[dict],
    recipients: list[dict],
    offline_files: list[str] | None = None,
) -> dict:
    await ensure_service_cert_authorized()

    now = datetime.now(UTC)
    push_id = uuid.uuid4().hex[:12]
    mission_name = f"{MISSION_PREFIX}-{now.strftime('%Y%m%dT%H%M%SZ')}-{push_id[:6]}"
    params = {
        "creatorUid": CREATOR_UID,
        "description": "TAK basemap and environmental overlay distribution",
        "tool": "public",
        "inviteOnly": "true",
        "defaultRole": "MISSION_READONLY_SUBSCRIBER",
    }
    created = False
    try:
        async with _tak_client() as client:
            response = await client.put(f"/Marti/api/missions/{quote(mission_name, safe='')}", params=params, content=b"")
            response.raise_for_status()
            created = True
            for layer in layers:
                response = await client.post(
                    f"/Marti/api/missions/{quote(mission_name, safe='')}/maplayers",
                    params={"creatorUid": CREATOR_UID},
                    json=layer,
                )
                response.raise_for_status()
            if offline_files:
                mission_package = await asyncio.to_thread(
                    _offline_mission_package,
                    mission_name,
                    offline_files,
                )
                response = await client.put(
                    f"/Marti/api/missions/{quote(mission_name, safe='')}/contents/missionpackage",
                    params={"creatorUid": CREATOR_UID},
                    content=mission_package,
                    headers={"Content-Type": "application/octet-stream"},
                )
                response.raise_for_status()
            for recipient in recipients:
                response = await client.put(
                    f"/Marti/api/missions/{quote(mission_name, safe='')}/invite/clientUid/{quote(recipient['uid'], safe='')}",
                    params={"creatorUid": CREATOR_UID, "role": "MISSION_READONLY_SUBSCRIBER"},
                )
                response.raise_for_status()
            response = await client.post(
                f"/Marti/api/missions/{quote(mission_name, safe='')}/invite",
                params={"creatorUid": CREATOR_UID},
            )
            response.raise_for_status()
            response = await client.post(
                f"/Marti/api/missions/{quote(mission_name, safe='')}/send",
                params=[("contacts", recipient["uid"]) for recipient in recipients],
            )
            response.raise_for_status()
    except (httpx.HTTPError, OSError, ssl.SSLError) as exc:
        if created:
            try:
                async with _tak_client() as cleanup_client:
                    await cleanup_client.delete(
                        f"/Marti/api/missions/{quote(mission_name, safe='')}",
                        params={"creatorUid": CREATOR_UID, "deepDelete": "true"},
                    )
            except Exception:
                pass
        raise HTTPException(status_code=502, detail=f"TAK Server basemap distribution failed: {exc}") from exc
    return {"mission_name": mission_name, "pushed_at": now.isoformat()}


async def delete_basemap_mission(mission_name: str) -> None:
    try:
        async with _tak_client() as client:
            response = await client.delete(
                f"/Marti/api/missions/{quote(mission_name, safe='')}",
                params={"creatorUid": CREATOR_UID, "deepDelete": "true"},
            )
            response.raise_for_status()
    except (httpx.HTTPError, OSError, ssl.SSLError) as exc:
        raise HTTPException(status_code=502, detail=f"Unable to delete TAK mission: {exc}") from exc


async def _validate_public_https_url(url: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise HTTPException(status_code=400, detail="XML URL must be a public HTTPS URL")
    try:
        addresses = await asyncio.get_running_loop().getaddrinfo(parsed.hostname, parsed.port or 443, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        raise HTTPException(status_code=400, detail="XML URL hostname could not be resolved") from exc
    if not addresses or any(not ipaddress.ip_address(address[4][0]).is_global for address in addresses):
        raise HTTPException(status_code=400, detail="XML URL must not resolve to a private or reserved address")
    return addresses[0][4][0]


async def _fetch_xml(url: str) -> bytes:
    address = await _validate_public_https_url(url)
    parsed = urlsplit(url)
    address_host = f"[{address}]" if ":" in address else address
    pinned_url = urlunsplit((parsed.scheme, f"{address_host}:{parsed.port or 443}", parsed.path, parsed.query, ""))
    try:
        async with httpx.AsyncClient(timeout=15, follow_redirects=False) as client:
            async with client.stream(
                "GET",
                pinned_url,
                headers={"Accept": "application/xml, text/xml", "Host": parsed.netloc},
                extensions={"sni_hostname": parsed.hostname},
            ) as response:
                response.raise_for_status()
                chunks = []
                total = 0
                async for chunk in response.aiter_bytes():
                    total += len(chunk)
                    if total > MAX_XML_BYTES:
                        raise HTTPException(status_code=413, detail="Remote XML is larger than 1 MB")
                    chunks.append(chunk)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Unable to download XML map source: {exc}") from exc
    return b"".join(chunks)


def _safe_custom_name(name: str) -> tuple[str, str]:
    display_name = name.strip()
    if not 1 <= len(display_name) <= 80 or not re.fullmatch(r"[A-Za-z0-9 ._()-]+", display_name):
        raise HTTPException(status_code=400, detail="Basemap name must use letters, numbers, spaces, dots, dashes, or parentheses")
    filename = re.sub(r"[^A-Za-z0-9._-]+", "_", display_name).strip("._") + ".xml"
    return display_name, filename


def _store_custom_xml(name: str, xml_data: bytes) -> dict:
    display_name, filename = _safe_custom_name(name)
    try:
        layer = parse_map_source(xml_data, fallback_name=display_name)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    root = ET.fromstring(xml_data)
    name_node = root.find("name")
    if name_node is None:
        name_node = ET.SubElement(root, "name")
    name_node.text = display_name
    stored_xml = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    target_dir = os.path.join(packages.MAPS_DIR, "Custom")
    os.makedirs(target_dir, exist_ok=True)
    target = os.path.join(target_dir, filename)
    with open(target, "wb") as target_file:
        target_file.write(stored_xml)
    return {"id": f"library:Custom/{filename}", "name": display_name, "layer_name": layer["name"]}


def _distribution_json(distribution: BasemapDistribution) -> dict:
    return {
        "id": distribution.id,
        "request_id": distribution.request_id,
        "mission_name": distribution.mission_name,
        "status": distribution.status,
        "item_ids": json.loads(distribution.item_ids),
        "recipient_uids": json.loads(distribution.recipient_uids),
        "recipients": json.loads(distribution.recipient_names),
        "layer_count": distribution.layer_count,
        "overlay_opacity": distribution.overlay_opacity,
        "recipient_count": len(json.loads(distribution.recipient_uids)),
        "accepted_count": distribution.accepted_count,
        "error": distribution.error,
        "created_at": distribution.created_at,
        "updated_at": distribution.updated_at,
        "pushed_at": distribution.updated_at,
    }


async def _prepare_distribution(body: PushRequest) -> tuple[list[dict], list[dict], list[str]]:
    expanded_ids = _expand_item_ids(body.item_ids)
    source_ids = [source_id for source_id in expanded_ids if not source_id.startswith("offline:")]
    offline_files = [_load_offline_source(source_id) for source_id in expanded_ids if source_id.startswith("offline:")]
    observed = {contact["uid"]: contact for contact in await get_connected_euds()}
    recipient_uids = list(dict.fromkeys(body.recipient_uids))
    if not recipient_uids or len(recipient_uids) > 100:
        raise HTTPException(status_code=400, detail="Select between 1 and 100 connected recipients")
    unknown = [uid for uid in recipient_uids if uid not in observed]
    if unknown:
        raise HTTPException(status_code=409, detail="Recipient list changed; refresh connected EUDs")
    recipients = [observed[uid] for uid in recipient_uids]

    resolved = await asyncio.gather(*(_resolve_source(source_id) for source_id in source_ids))
    push_id = uuid.uuid4().hex[:12]
    layers = []
    after = ""
    for source_id, source in zip(source_ids, resolved, strict=True):
        layer = _mission_layer(
            source,
            source_id=source_id,
            push_id=push_id,
            after=after,
            overlay_opacity=body.overlay_opacity,
        )
        layers.append(layer)
        after = layer["uid"]
    return layers, recipients, offline_files


async def _push_and_record(body: PushRequest, db: AsyncSession, actor) -> dict:
    request_id = body.request_id or uuid.uuid4().hex
    existing_result = await db.execute(
        select(BasemapDistribution).where(BasemapDistribution.request_id == request_id)
    )
    existing = existing_result.scalar_one_or_none()
    if existing is not None:
        if existing.status == "completed":
            return _distribution_json(existing)
        if existing.status == "pending":
            raise HTTPException(status_code=409, detail="This distribution request is already running")
        raise HTTPException(status_code=409, detail="This request ID was already used; retry with a new request ID")

    distribution = BasemapDistribution(
        request_id=request_id,
        status="pending",
        item_ids=json.dumps(body.item_ids),
        recipient_uids=json.dumps(list(dict.fromkeys(body.recipient_uids))),
        overlay_opacity=body.overlay_opacity,
        created_by=actor.id,
    )
    db.add(distribution)
    await db.commit()
    await db.refresh(distribution)

    try:
        layers, recipients, offline_files = await _prepare_distribution(body)
        published = await publish_basemap_mission(layers, recipients, offline_files)
    except HTTPException as exc:
        distribution.status = "failed"
        distribution.error = str(exc.detail)
        distribution.updated_at = datetime.now(UTC)
        await db.commit()
        raise
    except Exception as exc:
        distribution.status = "failed"
        distribution.error = str(exc)
        distribution.updated_at = datetime.now(UTC)
        await db.commit()
        raise HTTPException(status_code=500, detail="Unexpected basemap distribution failure") from exc

    recipient_names = [recipient.get("callsign") or recipient["uid"] for recipient in recipients]
    distribution.status = "completed"
    distribution.mission_name = published["mission_name"]
    distribution.layer_count = len(layers)
    distribution.recipient_names = json.dumps(recipient_names)
    distribution.updated_at = datetime.now(UTC)
    await db.commit()
    await db.refresh(distribution)
    await write_audit(
        db,
        actor.id,
        "push_basemaps",
        f"{published['mission_name']}: {len(layers)} layers to {len(recipients)} recipients",
    )
    return _distribution_json(distribution)


def _subscription_uids(payload) -> set[str]:
    if isinstance(payload, dict):
        payload = payload.get("data", payload.get("subscriptions", []))
    if not isinstance(payload, list):
        return set()
    result = set()
    for entry in payload:
        if isinstance(entry, str):
            result.add(entry)
        elif isinstance(entry, dict):
            uid = entry.get("clientUid") or entry.get("uid")
            if isinstance(uid, str):
                result.add(uid)
    return result


@router.get("/tiles/{token}/{source_id}/{zoom}/{x}/{y}", include_in_schema=False)
async def proxy_tile(token: str, source_id: str, zoom: int, x: int, y: int):
    if not hmac.compare_digest(token, _proxy_token(source_id)):
        raise HTTPException(status_code=404, detail="Tile source not found")
    content, content_type, ttl = await _cached_tile(source_id, zoom, x, y)
    return Response(
        content=content,
        media_type=content_type,
        headers={"Cache-Control": f"public, max-age={ttl}", "X-Content-Type-Options": "nosniff"},
    )


@router.get("/source-health")
async def source_health(_=Depends(_superadmin)):
    async def check(source_id: str) -> dict:
        started = time.monotonic()
        try:
            url, _ = await _upstream_tile_url(source_id, 2, 2, 1)
            async with httpx.AsyncClient(timeout=15, follow_redirects=False) as client:
                response = await client.get(url, headers={"Accept": "image/png,image/jpeg"})
                response.raise_for_status()
            content_type = response.headers.get("content-type", "").split(";", 1)[0]
            if content_type not in {"image/png", "image/jpeg"}:
                raise ValueError(f"unexpected content type {content_type or 'unknown'}")
            return {
                "id": source_id,
                "status": "healthy",
                "latency_ms": round((time.monotonic() - started) * 1000),
                "content_type": content_type,
            }
        except (HTTPException, httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
            return {
                "id": source_id,
                "status": "unhealthy",
                "latency_ms": round((time.monotonic() - started) * 1000),
                "error": str(exc.detail) if isinstance(exc, HTTPException) else str(exc),
            }

    checks = await asyncio.gather(*(check(source_id) for source_id in BUILTIN_SOURCES))
    return {"sources": checks, "checked_at": datetime.now(UTC).isoformat()}


@router.get("/catalog")
async def get_catalog(_=Depends(_superadmin)):
    return {
        "presets": [
            {"id": preset_id, "name": name, "description": description, "layer_count": len(source_ids)}
            for preset_id, name, description, source_ids in PRESETS
        ],
        "library_sources": _library_sources(),
        "offline_sources": [
            {"id": source_id, "name": source["name"], "description": source.get("description", "")}
            for source_id, source in BUILTIN_SOURCES.items()
        ],
        "proxy": _proxy_configuration(),
        "provider_notice": (
            "Upstream availability and licensing remain the operator's responsibility. "
            "Google endpoints require authorization under Google's applicable terms; "
            "use organization-approved custom XML sources when credentials or contractual attribution are required."
        ),
    }


@router.get("/diagnostics")
async def basemap_diagnostics(_=Depends(_superadmin)):
    certificate_files = [
        os.path.join(CERT_DIR, f"{SERVICE_CERT_NAME}.{suffix}")
        for suffix in ("pem", "key", "certpass")
    ]
    proxy = _proxy_configuration()
    checks = {
        "service_certificate": {
            "ready": all(os.path.isfile(path) for path in certificate_files),
            "name": SERVICE_CERT_NAME,
        },
        "tile_proxy": proxy,
        "tile_cache": {
            "ready": os.path.isdir(TILE_CACHE_DIR) and os.access(TILE_CACHE_DIR, os.W_OK),
            "path": TILE_CACHE_DIR,
        },
        "tak_api": {"address": TAK_API_ADDRESS, "strict_hostname_verification": True},
    }
    try:
        recipients = await get_connected_euds()
        checks["tak_api"].update({"ready": True, "connected_euds": len(recipients)})
    except HTTPException as exc:
        checks["tak_api"].update({"ready": False, "error": str(exc.detail)})
    return {
        "ready": all(check.get("ready", False) for check in checks.values()),
        "checks": checks,
        "sample_tile_url": (
            f"{TILE_PROXY_URL.rstrip('/')}/api/basemaps/tiles/"
            f"{_proxy_token('esri-topo')}/esri-topo/2/2/1"
        ),
    }


@router.post("/setup")
async def setup_basemap_service(db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    await ensure_service_cert_authorized()
    await write_audit(db, actor.id, "setup_basemap_service_cert", SERVICE_CERT_NAME)
    return {"status": "ready", "certificate": SERVICE_CERT_NAME}


@router.get("/recipients")
async def get_recipients(_=Depends(_superadmin)):
    return {"recipients": await get_connected_euds()}


@router.post("/custom/file", status_code=201)
async def add_custom_file(
    name: str = Form(...),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    actor=Depends(_superadmin),
):
    xml_data = await file.read(MAX_XML_BYTES + 1)
    result = _store_custom_xml(name, xml_data)
    await write_audit(db, actor.id, "add_basemap_xml", result["id"])
    return result


@router.post("/custom/url", status_code=201)
async def add_custom_url(
    body: CustomUrlRequest,
    db: AsyncSession = Depends(get_db),
    actor=Depends(_superadmin),
):
    xml_data = await _fetch_xml(body.url)
    result = _store_custom_xml(body.name, xml_data)
    await write_audit(db, actor.id, "add_basemap_url", result["id"])
    return result


@router.delete("/library/{provider}/{filename}")
async def delete_library_source(
    provider: str,
    filename: str,
    db: AsyncSession = Depends(get_db),
    actor=Depends(_superadmin),
):
    path = _managed_source_path(provider, filename)
    try:
        os.remove(path)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Map source not found") from exc
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Unable to delete map source: {exc}") from exc
    source_id = f"{'library' if provider == 'Custom' else 'offline'}:{provider}/{filename}"
    await write_audit(db, actor.id, "delete_basemap_source", source_id)
    return {"deleted": source_id}


@router.post("/offline/build", status_code=201)
async def build_offline_map(
    body: OfflineBuildRequest,
    db: AsyncSession = Depends(get_db),
    actor=Depends(_superadmin),
):
    result = await _build_offline_mbtiles(body)
    await write_audit(
        db,
        actor.id,
        "build_offline_basemap",
        f"{result['id']}: {result['tile_count']} tiles, {result['size_bytes']} bytes",
    )
    return result


@router.post("/push")
async def push_basemaps(
    body: PushRequest,
    db: AsyncSession = Depends(get_db),
    actor=Depends(_superadmin),
):
    return await _push_and_record(body, db, actor)


@router.get("/history")
async def distribution_history(db: AsyncSession = Depends(get_db), _=Depends(_superadmin)):
    result = await db.execute(
        select(BasemapDistribution).order_by(BasemapDistribution.created_at.desc()).limit(100)
    )
    return {"distributions": [_distribution_json(row) for row in result.scalars()]}


@router.post("/history/{distribution_id}/refresh")
async def refresh_distribution(
    distribution_id: str,
    db: AsyncSession = Depends(get_db),
    _=Depends(_superadmin),
):
    distribution = await db.get(BasemapDistribution, distribution_id)
    if distribution is None:
        raise HTTPException(status_code=404, detail="Distribution not found")
    if distribution.mission_name and distribution.status != "deleted":
        try:
            async with _tak_client() as client:
                response = await client.get(
                    f"/Marti/api/missions/{quote(distribution.mission_name, safe='')}/subscriptions"
                )
                response.raise_for_status()
                accepted = _subscription_uids(response.json())
        except (httpx.HTTPError, OSError, ssl.SSLError, ValueError) as exc:
            raise HTTPException(status_code=502, detail=f"Unable to refresh mission delivery: {exc}") from exc
        invited = set(json.loads(distribution.recipient_uids))
        distribution.accepted_count = len(invited & accepted)
        distribution.updated_at = datetime.now(UTC)
        await db.commit()
        await db.refresh(distribution)
    return _distribution_json(distribution)


@router.post("/history/{distribution_id}/resend")
async def resend_distribution(
    distribution_id: str,
    db: AsyncSession = Depends(get_db),
    actor=Depends(_superadmin),
):
    original = await db.get(BasemapDistribution, distribution_id)
    if original is None:
        raise HTTPException(status_code=404, detail="Distribution not found")
    body = PushRequest(
        item_ids=json.loads(original.item_ids),
        recipient_uids=json.loads(original.recipient_uids),
        overlay_opacity=original.overlay_opacity,
        request_id=uuid.uuid4().hex,
    )
    return await _push_and_record(body, db, actor)


@router.delete("/history/{distribution_id}")
async def delete_distribution(
    distribution_id: str,
    db: AsyncSession = Depends(get_db),
    actor=Depends(_superadmin),
):
    distribution = await db.get(BasemapDistribution, distribution_id)
    if distribution is None:
        raise HTTPException(status_code=404, detail="Distribution not found")
    if distribution.mission_name and distribution.status != "deleted":
        await delete_basemap_mission(distribution.mission_name)
    distribution.status = "deleted"
    distribution.updated_at = datetime.now(UTC)
    await db.commit()
    await db.refresh(distribution)
    await write_audit(db, actor.id, "delete_basemap_mission", distribution.mission_name)
    return _distribution_json(distribution)


@router.post("/cleanup")
async def cleanup_distributions(
    body: CleanupRequest,
    db: AsyncSession = Depends(get_db),
    actor=Depends(_superadmin),
):
    cutoff = datetime.now(UTC) - timedelta(days=body.older_than_days)
    result = await db.execute(
        select(BasemapDistribution).where(
            BasemapDistribution.created_at < cutoff,
            BasemapDistribution.status.in_(("completed", "failed")),
        )
    )
    cleaned = 0
    for distribution in result.scalars():
        if distribution.mission_name:
            await delete_basemap_mission(distribution.mission_name)
        distribution.status = "deleted"
        distribution.updated_at = datetime.now(UTC)
        cleaned += 1
    await db.commit()
    await write_audit(db, actor.id, "cleanup_basemap_missions", f"{cleaned} older than {body.older_than_days} days")
    return {"cleaned": cleaned}
