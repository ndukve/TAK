import asyncio
import hashlib
import json
import os
import tempfile
import zipfile

import aiofiles
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.background import BackgroundTask
from starlette.responses import FileResponse

from .deps import get_db, require_role, write_audit

router = APIRouter(tags=["packages"])
_admin = require_role("admin", "superadmin")
_admin_or_field = require_role("admin", "superadmin", "field")


def _base_callsign(filename: str) -> str:
    """Strip the trailing -ATAK/-WinTAK/-iTAK/-Service suffix. 'Alpha1-iTAK.zip' -> 'Alpha1'."""
    name = filename.rsplit(".", 1)[0]
    for suffix in ("-ATAK", "-WinTAK", "-iTAK", "-Service"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name

MAX_UPLOAD_BYTES = 100 * 1024 * 1024  # 100 MB

TAK_DATA = "/opt/tak/data"
PKGS_DIR = os.path.join(TAK_DATA, "certs/files/clientpkgs")
PLUGINS_DIR = "/opt/tak/plugins"   # tak_plugins volume → /opt/tak/plugins in admin container
MAPS_DIR = "/opt/tak/maps"  # host packages/tak-maps/ → bind-mounted read-write here

# Admin-maintained allowlist of known-good plugin SHA-256 hashes (from
# tak.gov release pages) — one hex digest per line, '#' comments and blank
# lines ignored. Lives in the same persistent volume as the plugins
# themselves but doesn't match the .apk/.wpk/.zip listing filter above.
CHECKSUMS_FILE = os.path.join(PLUGINS_DIR, ".allowed-checksums.txt")


def _load_allowed_checksums() -> set[str]:
    try:
        with open(CHECKSUMS_FILE) as f:
            return {
                line.strip().lower()
                for line in f
                if line.strip() and not line.strip().startswith("#")
            }
    except OSError:
        return set()


def _sha256_stored(path: str) -> str | None:
    sidecar = path + ".sha256"
    try:
        return open(sidecar).read().strip() or None
    except OSError:
        return None


def _zip_files_to_tempfile(files: list[tuple[str, str]]) -> str:
    """files: (absolute_path, arcname) pairs. Writes them into a new temp zip
    on disk (not memory — maps can run into the multi-GB range) and returns
    its path. ZIP_STORED: the contents (mbtiles, apk/wpk) are already
    compressed, so re-compressing here would just burn CPU for no size win."""
    fd, path = tempfile.mkstemp(suffix=".zip")
    os.close(fd)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        for abs_path, arcname in files:
            archive.write(abs_path, arcname)
    return path


def _sha256_compute_and_store(data: bytes, path: str) -> str:
    digest = hashlib.sha256(data).hexdigest()
    try:
        with open(path + ".sha256", "w") as f:
            f.write(digest)
    except OSError:
        pass
    return digest


async def _stream_upload_to_disk(file: UploadFile, dest: str, max_bytes: int) -> tuple[int, str]:
    """Copies an upload to disk in chunks instead of buffering the whole file
    in memory — needed for multi-gigabyte .mbtiles packages, where file.read()
    with no size cap would hold the entire upload as one bytes object."""
    digest = hashlib.sha256()
    total = 0
    oversized = False
    chunk_size = 8 * 1024 * 1024
    async with aiofiles.open(dest, "wb") as f:
        while True:
            chunk = await file.read(chunk_size)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                oversized = True
                break
            digest.update(chunk)
            await f.write(chunk)
    if oversized:
        os.remove(dest)
        raise HTTPException(status_code=413, detail=f"File too large (max {max_bytes // (1024**3)} GB)")
    hexdigest = digest.hexdigest()
    try:
        with open(dest + ".sha256", "w") as f:
            f.write(hexdigest)
    except OSError:
        pass
    return total, hexdigest


def _size(path: str) -> str:
    try:
        b = os.path.getsize(path)
        for unit in ("B", "KB", "MB", "GB"):
            if b < 1024:
                return f"{b:.0f} {unit}"
            b /= 1024
        return f"{b:.1f} GB"
    except OSError:
        return "?"


@router.get("/api/packages")
async def list_packages(actor=Depends(_admin_or_field)):
    if not os.path.isdir(PKGS_DIR):
        return {"packages": []}
    files = sorted(f for f in os.listdir(PKGS_DIR) if f.endswith(".zip"))
    if actor.role == "field":
        files = [f for f in files if _base_callsign(f) == actor.owned_callsign]
    return {"packages": [
        {"name": f.replace(".zip", ""), "filename": f, "size": _size(os.path.join(PKGS_DIR, f))}
        for f in files
    ]}


@router.get("/api/packages/{name}/download")
async def download_package(name: str, actor=Depends(_admin_or_field)):
    safe_name = os.path.basename(name)
    if actor.role == "field" and _base_callsign(safe_name) != actor.owned_callsign:
        raise HTTPException(status_code=404, detail="Package not found")
    path = os.path.join(PKGS_DIR, f"{safe_name}.zip")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Package not found")
    return FileResponse(path, filename=f"{safe_name}.zip", media_type="application/zip")


@router.post("/api/packages/upload", status_code=201)
async def upload_package(file: UploadFile = File(...), db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    if not (file.filename or "").endswith(".zip"):
        raise HTTPException(status_code=400, detail="Only .zip files allowed")
    os.makedirs(PKGS_DIR, exist_ok=True)
    safe_name = os.path.basename(file.filename)
    dest = os.path.join(PKGS_DIR, safe_name)
    data = await file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 100 MB)")
    async with aiofiles.open(dest, "wb") as f:
        await f.write(data)
    await write_audit(db, actor.id, "upload_package", safe_name)
    return {"name": safe_name.replace(".zip", ""), "filename": safe_name, "size": _size(dest)}


@router.delete("/api/packages/{name}", status_code=204)
async def delete_package(name: str, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    safe_name = os.path.basename(name)
    path = os.path.join(PKGS_DIR, f"{safe_name}.zip")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Package not found")
    os.remove(path)
    await write_audit(db, actor.id, "delete_package", f"{safe_name}.zip")


@router.get("/api/plugins")
async def list_plugins(_=Depends(_admin_or_field)):
    if not os.path.isdir(PLUGINS_DIR):
        return {"plugins": []}
    allowed = _load_allowed_checksums()
    files = sorted(f for f in os.listdir(PLUGINS_DIR) if f.endswith(".apk") or f.endswith(".wpk") or f.endswith(".zip"))
    plugins = []
    for f in files:
        sha256 = _sha256_stored(os.path.join(PLUGINS_DIR, f))
        plugins.append({
            "filename": f,
            "size": _size(os.path.join(PLUGINS_DIR, f)),
            "sha256": sha256,
            "verified": bool(sha256 and sha256.lower() in allowed),
        })
    return {"plugins": plugins}


@router.get("/api/plugins/download-all")
async def download_all_plugins(_=Depends(_admin_or_field)):
    files: list[tuple[str, str]] = []
    if os.path.isdir(PLUGINS_DIR):
        files = [
            (os.path.join(PLUGINS_DIR, f), f)
            for f in sorted(os.listdir(PLUGINS_DIR))
            if f.endswith(".apk") or f.endswith(".wpk") or f.endswith(".zip")
        ]
    if not files:
        raise HTTPException(status_code=404, detail="No plugins uploaded")
    zip_path = await asyncio.to_thread(_zip_files_to_tempfile, files)
    return FileResponse(zip_path, filename="plugins.zip", media_type="application/zip", background=BackgroundTask(os.remove, zip_path))


@router.get("/api/plugins/checksums")
async def get_allowed_checksums(_=Depends(_admin)):
    try:
        with open(CHECKSUMS_FILE) as f:
            return {"content": f.read()}
    except OSError:
        return {"content": ""}


class ChecksumsRequest(BaseModel):
    content: str


@router.put("/api/plugins/checksums")
async def set_allowed_checksums(body: ChecksumsRequest, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    os.makedirs(PLUGINS_DIR, exist_ok=True)
    with open(CHECKSUMS_FILE, "w") as f:
        f.write(body.content)
    count = len(_load_allowed_checksums())
    await write_audit(db, actor.id, "update_plugin_checksums", f"{count} hashes")
    return {"count": count}


@router.get("/api/plugins/{filename}/download")
async def download_plugin(filename: str, _=Depends(_admin_or_field)):
    safe_name = os.path.basename(filename)
    path = os.path.join(PLUGINS_DIR, safe_name)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Plugin not found")
    return FileResponse(path, filename=safe_name)


@router.post("/api/plugins", status_code=201)
async def upload_plugin(
    file: UploadFile = File(...),
    expected_sha256: str | None = Form(None),
    db: AsyncSession = Depends(get_db),
    actor=Depends(_admin),
):
    filename = file.filename or ""
    if not (filename.endswith(".apk") or filename.endswith(".wpk") or filename.endswith(".zip")):
        raise HTTPException(status_code=400, detail="Only .apk, .wpk, or .zip files allowed")
    os.makedirs(PLUGINS_DIR, exist_ok=True)
    dest = os.path.join(PLUGINS_DIR, os.path.basename(file.filename))
    data = await file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 100 MB)")
    actual_sha256 = hashlib.sha256(data).hexdigest()
    if expected_sha256 and expected_sha256.lower() != actual_sha256:
        raise HTTPException(status_code=400, detail=f"SHA-256 mismatch — got {actual_sha256}")
    verified = actual_sha256 in _load_allowed_checksums()
    async with aiofiles.open(dest, "wb") as f:
        await f.write(data)
    _sha256_compute_and_store(data, dest)
    await write_audit(db, actor.id, "upload_plugin", file.filename)
    return {"filename": file.filename, "size": _size(dest), "sha256": actual_sha256, "verified": verified}


@router.delete("/api/plugins/{filename}", status_code=204)
async def delete_plugin(filename: str, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    safe_name = os.path.basename(filename)
    path = os.path.join(PLUGINS_DIR, safe_name)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Plugin not found")
    os.remove(path)
    await write_audit(db, actor.id, "delete_plugin", safe_name)


MAX_MBTILES_BYTES = 6 * 1024 * 1024 * 1024  # 6 GB — offline tile packages run far larger than XML pointers
MAX_MAP_CHUNK_BYTES = 8 * 1024 * 1024
_MAP_EXTENSIONS = (".xml", ".mbtiles")


class MapUploadInit(BaseModel):
    provider: str
    filename: str
    total_size: int
    fingerprint: str


def _map_upload_paths(provider: str, filename: str, total_size: int) -> tuple[str, str, str]:
    if not filename.endswith(_MAP_EXTENSIONS):
        raise HTTPException(status_code=400, detail="Only .xml or .mbtiles files allowed")
    if not provider.replace("-", "").replace("_", "").isalnum():
        raise HTTPException(status_code=400, detail="Provider name must be alphanumeric")
    max_bytes = MAX_MBTILES_BYTES if filename.endswith(".mbtiles") else MAX_UPLOAD_BYTES
    if total_size < 1 or total_size > max_bytes:
        raise HTTPException(status_code=413, detail=f"File too large (max {max_bytes // (1024**2)} MB)")
    safe_filename = os.path.basename(filename)
    if safe_filename != filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    dest_dir = os.path.join(MAPS_DIR, provider)
    dest = os.path.join(dest_dir, safe_filename)
    return dest, dest + ".upload", dest + ".upload.json"


def _read_upload_metadata(path: str) -> dict | None:
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _write_upload_metadata(path: str, metadata: dict) -> None:
    with open(path, "w") as f:
        json.dump(metadata, f)


@router.get("/api/maps")
async def list_maps(_=Depends(_admin_or_field)):
    result = []
    if os.path.isdir(MAPS_DIR):
        for provider in sorted(os.listdir(MAPS_DIR)):
            pdir = os.path.join(MAPS_DIR, provider)
            if not os.path.isdir(pdir):
                continue
            for fname in sorted(f for f in os.listdir(pdir) if f.endswith(_MAP_EXTENSIONS)):
                fpath = os.path.join(pdir, fname)
                kind = "mbtiles" if fname.endswith(".mbtiles") else "xml"
                result.append({"provider": provider, "filename": fname, "kind": kind, "size": _size(fpath), "sha256": _sha256_stored(fpath)})
    return {"maps": result}


@router.get("/api/maps/download-all")
async def download_all_maps(_=Depends(_admin_or_field)):
    files: list[tuple[str, str]] = []
    if os.path.isdir(MAPS_DIR):
        for provider in sorted(os.listdir(MAPS_DIR)):
            pdir = os.path.join(MAPS_DIR, provider)
            if not os.path.isdir(pdir):
                continue
            for fname in sorted(f for f in os.listdir(pdir) if f.endswith(_MAP_EXTENSIONS)):
                files.append((os.path.join(pdir, fname), f"{provider}/{fname}"))
    if not files:
        raise HTTPException(status_code=404, detail="No maps uploaded")
    zip_path = await asyncio.to_thread(_zip_files_to_tempfile, files)
    return FileResponse(zip_path, filename="maps.zip", media_type="application/zip", background=BackgroundTask(os.remove, zip_path))


@router.post("/api/maps/uploads")
async def initialize_map_upload(body: MapUploadInit, _=Depends(_admin)):
    if not body.fingerprint or len(body.fingerprint) > 200:
        raise HTTPException(status_code=400, detail="Invalid upload fingerprint")
    dest, partial, metadata_path = _map_upload_paths(body.provider, body.filename, body.total_size)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    metadata = _read_upload_metadata(metadata_path)
    matches = bool(
        metadata
        and metadata.get("total_size") == body.total_size
        and metadata.get("fingerprint") == body.fingerprint
    )
    if matches and metadata.get("complete") and os.path.isfile(dest) and os.path.getsize(dest) == body.total_size:
        return {"offset": body.total_size, "complete": True, "sha256": _sha256_stored(dest)}
    if not matches:
        for path in (partial, metadata_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        with open(partial, "wb"):
            pass
        metadata = {"total_size": body.total_size, "fingerprint": body.fingerprint, "complete": False}
        _write_upload_metadata(metadata_path, metadata)
    elif not os.path.isfile(partial):
        with open(partial, "wb"):
            pass

    offset = min(os.path.getsize(partial), body.total_size)
    if os.path.getsize(partial) != offset:
        with open(partial, "r+b") as f:
            f.truncate(offset)
    return {"offset": offset, "complete": False}


@router.put("/api/maps/uploads/{provider}/{filename}")
async def upload_map_chunk(
    provider: str,
    filename: str,
    offset: int,
    total_size: int,
    fingerprint: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    actor=Depends(_admin),
):
    dest, partial, metadata_path = _map_upload_paths(provider, filename, total_size)
    metadata = _read_upload_metadata(metadata_path)
    if not metadata or metadata.get("fingerprint") != fingerprint or metadata.get("total_size") != total_size:
        raise HTTPException(status_code=409, detail="Upload session changed; initialize it again")
    current_offset = os.path.getsize(partial) if os.path.isfile(partial) else 0
    if offset != current_offset:
        raise HTTPException(status_code=409, detail=f"Resume from byte {current_offset}")

    received = 0
    try:
        async with aiofiles.open(partial, "ab") as f:
            async for chunk in request.stream():
                received += len(chunk)
                if received > MAX_MAP_CHUNK_BYTES or offset + received > total_size:
                    raise HTTPException(status_code=413, detail="Upload chunk is too large")
                await f.write(chunk)
    except HTTPException:
        with open(partial, "r+b") as f:
            f.truncate(offset)
        raise
    if received == 0:
        raise HTTPException(status_code=400, detail="Upload chunk is empty")

    new_offset = offset + received
    if new_offset < total_size:
        return {"offset": new_offset, "complete": False}

    digest = hashlib.sha256()
    async with aiofiles.open(partial, "rb") as f:
        while chunk := await f.read(MAX_MAP_CHUNK_BYTES):
            digest.update(chunk)
    sha256 = digest.hexdigest()
    os.replace(partial, dest)
    with open(dest + ".sha256", "w") as f:
        f.write(sha256)
    metadata["complete"] = True
    _write_upload_metadata(metadata_path, metadata)
    await write_audit(db, actor.id, "upload_map", f"{provider}/{filename}")
    return {
        "offset": new_offset,
        "complete": True,
        "provider": provider,
        "filename": filename,
        "size": _size(dest),
        "sha256": sha256,
    }


@router.get("/api/maps/{provider}/{filename}/download")
async def download_map(provider: str, filename: str, _=Depends(_admin_or_field)):
    safe_provider = os.path.basename(provider)
    safe_filename = os.path.basename(filename)
    path = os.path.join(MAPS_DIR, safe_provider, safe_filename)
    if not os.path.realpath(path).startswith(os.path.realpath(MAPS_DIR) + os.sep):
        raise HTTPException(status_code=403, detail="Invalid path")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Map not found")
    media_type = "text/xml" if safe_filename.endswith(".xml") else "application/octet-stream"
    return FileResponse(path, filename=safe_filename, media_type=media_type)


@router.post("/api/maps", status_code=201)
async def upload_map(
    provider: str,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    actor=Depends(_admin),
):
    filename = file.filename or ""
    if not filename.endswith(_MAP_EXTENSIONS):
        raise HTTPException(status_code=400, detail="Only .xml or .mbtiles files allowed")
    if not provider.replace("-", "").replace("_", "").isalnum():
        raise HTTPException(status_code=400, detail="Provider name must be alphanumeric")
    dest_dir = os.path.join(MAPS_DIR, provider)
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, os.path.basename(filename))

    if filename.endswith(".mbtiles"):
        _, sha256 = await _stream_upload_to_disk(file, dest, MAX_MBTILES_BYTES)
    else:
        data = await file.read(MAX_UPLOAD_BYTES + 1)
        if len(data) > MAX_UPLOAD_BYTES:
            raise HTTPException(status_code=413, detail="File too large (max 100 MB)")
        sha256 = _sha256_compute_and_store(data, dest)
        async with aiofiles.open(dest, "wb") as f:
            await f.write(data)

    await write_audit(db, actor.id, "upload_map", f"{provider}/{filename}")
    return {"provider": provider, "filename": filename, "size": _size(dest), "sha256": sha256}


@router.delete("/api/maps/{provider}/{filename}", status_code=204)
async def delete_map(provider: str, filename: str, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    safe_provider = os.path.basename(provider)
    safe_filename = os.path.basename(filename)
    path = os.path.join(MAPS_DIR, safe_provider, safe_filename)
    if not os.path.realpath(path).startswith(os.path.realpath(MAPS_DIR) + os.sep):
        raise HTTPException(status_code=403, detail="Invalid path")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Map not found")
    os.remove(path)
    for sidecar in (path + ".sha256", path + ".upload", path + ".upload.json"):
        try:
            os.remove(sidecar)
        except FileNotFoundError:
            pass
    await write_audit(db, actor.id, "delete_map", f"{safe_provider}/{safe_filename}")
