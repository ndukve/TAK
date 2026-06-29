import os
import aiofiles
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException

from .deps import require_role, write_audit, get_db
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter(tags=["packages"])
_admin = require_role("admin", "superadmin")

TAK_DATA = "/opt/tak/data"
PKGS_DIR = os.path.join(TAK_DATA, "certs/files/clientpkgs")
PLUGINS_DIR = "/opt/tak/plugins"   # tak_plugins volume → /opt/tak/plugins in admin container
MAPS_DIR = os.path.join(TAK_DATA, "maps")  # takserver_data volume → /opt/tak/data/maps


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
async def list_packages(_=Depends(_admin)):
    if not os.path.isdir(PKGS_DIR):
        return {"packages": []}
    files = sorted(f for f in os.listdir(PKGS_DIR) if f.endswith(".zip"))
    return {"packages": [{"name": f.replace(".zip", ""), "filename": f, "size": _size(os.path.join(PKGS_DIR, f))} for f in files]}


@router.get("/api/plugins")
async def list_plugins(_=Depends(_admin)):
    if not os.path.isdir(PLUGINS_DIR):
        return {"plugins": []}
    files = sorted(f for f in os.listdir(PLUGINS_DIR) if f.endswith(".apk") or f.endswith(".zip"))
    return {"plugins": [{"filename": f, "size": _size(os.path.join(PLUGINS_DIR, f))} for f in files]}


@router.post("/api/plugins", status_code=201)
async def upload_plugin(file: UploadFile = File(...), db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    if not (file.filename.endswith(".apk") or file.filename.endswith(".zip")):
        raise HTTPException(status_code=400, detail="Only .apk or .zip files allowed")
    os.makedirs(PLUGINS_DIR, exist_ok=True)
    dest = os.path.join(PLUGINS_DIR, os.path.basename(file.filename))
    async with aiofiles.open(dest, "wb") as f:
        await f.write(await file.read())
    await write_audit(db, actor.id, "upload_plugin", file.filename)
    return {"filename": file.filename, "size": _size(dest)}


@router.get("/api/maps")
async def list_maps(_=Depends(_admin)):
    result = []
    if os.path.isdir(MAPS_DIR):
        for provider in sorted(os.listdir(MAPS_DIR)):
            pdir = os.path.join(MAPS_DIR, provider)
            if not os.path.isdir(pdir):
                continue
            for fname in sorted(f for f in os.listdir(pdir) if f.endswith(".xml")):
                result.append({"provider": provider, "filename": fname, "size": _size(os.path.join(pdir, fname))})
    return {"maps": result}


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
    async with aiofiles.open(dest, "wb") as f:
        await f.write(await file.read())
    await write_audit(db, actor.id, "upload_map", f"{provider}/{file.filename}")
    return {"provider": provider, "filename": file.filename, "size": _size(dest)}
