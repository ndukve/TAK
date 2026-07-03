import hashlib
import os
import aiofiles
from fastapi import APIRouter, Depends, Form, UploadFile, File, HTTPException
from starlette.responses import FileResponse

from .deps import require_role, write_audit, get_db
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter(tags=["packages"])
_admin = require_role("admin", "superadmin")
_admin_or_field = require_role("admin", "superadmin", "field")


def _base_callsign(filename: str) -> str:
    """Strip the trailing -ATAK/-WinTAK/-iTAK suffix. 'Alpha1-iTAK.zip' -> 'Alpha1'."""
    name = filename.rsplit(".", 1)[0]
    for suffix in ("-ATAK", "-WinTAK", "-iTAK"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name

MAX_UPLOAD_BYTES = 100 * 1024 * 1024  # 100 MB

TAK_DATA = "/opt/tak/data"
PKGS_DIR = os.path.join(TAK_DATA, "certs/files/clientpkgs")
PLUGINS_DIR = "/opt/tak/plugins"   # tak_plugins volume → /opt/tak/plugins in admin container
MAPS_DIR = "/opt/tak/maps"  # host packages/tak-maps/ → bind-mounted read-write here


def _sha256_stored(path: str) -> str | None:
    sidecar = path + ".sha256"
    try:
        return open(sidecar).read().strip() or None
    except OSError:
        return None


def _sha256_compute_and_store(data: bytes, path: str) -> str:
    digest = hashlib.sha256(data).hexdigest()
    try:
        with open(path + ".sha256", "w") as f:
            f.write(digest)
    except OSError:
        pass
    return digest


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
    if not file.filename.endswith(".zip"):
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
async def list_plugins(_=Depends(_admin)):
    if not os.path.isdir(PLUGINS_DIR):
        return {"plugins": []}
    files = sorted(f for f in os.listdir(PLUGINS_DIR) if f.endswith(".apk") or f.endswith(".zip"))
    return {"plugins": [{"filename": f, "size": _size(os.path.join(PLUGINS_DIR, f)), "sha256": _sha256_stored(os.path.join(PLUGINS_DIR, f))} for f in files]}


@router.get("/api/plugins/{filename}/download")
async def download_plugin(filename: str, _=Depends(_admin)):
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
    if not (file.filename.endswith(".apk") or file.filename.endswith(".zip")):
        raise HTTPException(status_code=400, detail="Only .apk or .zip files allowed")
    os.makedirs(PLUGINS_DIR, exist_ok=True)
    dest = os.path.join(PLUGINS_DIR, os.path.basename(file.filename))
    data = await file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 100 MB)")
    actual_sha256 = _sha256_compute_and_store(data, dest)
    if expected_sha256 and expected_sha256.lower() != actual_sha256:
        try:
            os.remove(dest)
            os.remove(dest + ".sha256")
        except OSError:
            pass
        raise HTTPException(status_code=400, detail=f"SHA-256 mismatch — got {actual_sha256}")
    async with aiofiles.open(dest, "wb") as f:
        await f.write(data)
    await write_audit(db, actor.id, "upload_plugin", file.filename)
    return {"filename": file.filename, "size": _size(dest), "sha256": actual_sha256}


@router.delete("/api/plugins/{filename}", status_code=204)
async def delete_plugin(filename: str, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    safe_name = os.path.basename(filename)
    path = os.path.join(PLUGINS_DIR, safe_name)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Plugin not found")
    os.remove(path)
    await write_audit(db, actor.id, "delete_plugin", safe_name)


@router.get("/api/maps")
async def list_maps(_=Depends(_admin_or_field)):
    result = []
    if os.path.isdir(MAPS_DIR):
        for provider in sorted(os.listdir(MAPS_DIR)):
            pdir = os.path.join(MAPS_DIR, provider)
            if not os.path.isdir(pdir):
                continue
            for fname in sorted(f for f in os.listdir(pdir) if f.endswith(".xml")):
                fpath = os.path.join(pdir, fname)
                result.append({"provider": provider, "filename": fname, "size": _size(fpath), "sha256": _sha256_stored(fpath)})
    return {"maps": result}


@router.get("/api/maps/{provider}/{filename}/download")
async def download_map(provider: str, filename: str, _=Depends(_admin_or_field)):
    safe_provider = os.path.basename(provider)
    safe_filename = os.path.basename(filename)
    path = os.path.join(MAPS_DIR, safe_provider, safe_filename)
    if not os.path.realpath(path).startswith(os.path.realpath(MAPS_DIR) + os.sep):
        raise HTTPException(status_code=403, detail="Invalid path")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Map not found")
    return FileResponse(path, filename=safe_filename, media_type="text/xml")


@router.post("/api/maps", status_code=201)
async def upload_map(
    provider: str,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    actor=Depends(_admin),
):
    if not file.filename.endswith(".xml"):
        raise HTTPException(status_code=400, detail="Only .xml files allowed")
    if not provider.replace("-", "").replace("_", "").isalnum():
        raise HTTPException(status_code=400, detail="Provider name must be alphanumeric")
    dest_dir = os.path.join(MAPS_DIR, provider)
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, os.path.basename(file.filename))
    data = await file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 100 MB)")
    sha256 = _sha256_compute_and_store(data, dest)
    async with aiofiles.open(dest, "wb") as f:
        await f.write(data)
    await write_audit(db, actor.id, "upload_map", f"{provider}/{file.filename}")
    return {"provider": provider, "filename": file.filename, "size": _size(dest), "sha256": sha256}


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
    await write_audit(db, actor.id, "delete_map", f"{safe_provider}/{safe_filename}")
