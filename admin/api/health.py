import asyncio
import json
import docker
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, Query
from docker.errors import DockerException
from jose import JWTError, jwt

from .deps import require_role, SECRET_KEY, ALGORITHM

router = APIRouter(prefix="/api/health", tags=["health"])
_client = docker.from_env()

SERVICES = [
    "takdb", "takserver_config", "takserver_messaging",
    "takserver_api", "takserver_retention", "takserver_pluginmanager",
    "pkg_server", "admin",
]


def _verify_ws_token(token: str) -> bool:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload.get("role") in ("admin", "superadmin")
    except JWTError:
        return False


def _get_states() -> list[dict]:
    out = []
    for name in SERVICES:
        try:
            c = _client.containers.get(name)
            out.append({"name": name, "status": c.status, "health": c.attrs.get("State", {}).get("Health", {}).get("Status", "none")})
        except DockerException:
            out.append({"name": name, "status": "not_found", "health": "none"})
    return out


@router.get("")
async def get_health(_=Depends(require_role("admin", "superadmin"))):
    loop = asyncio.get_running_loop()
    states = await loop.run_in_executor(None, _get_states)
    return {"services": states}


@router.websocket("/stream")
async def health_stream(ws: WebSocket, token: str = Query(...)):
    if not _verify_ws_token(token):
        await ws.close(code=4401)
        return
    await ws.accept()
    try:
        while True:
            loop = asyncio.get_running_loop()
            states = await loop.run_in_executor(None, _get_states)
            await ws.send_text(json.dumps({"services": states}))
            await asyncio.sleep(5)
    except WebSocketDisconnect:
        pass
