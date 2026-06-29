import asyncio
import json
import docker
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from docker.errors import DockerException

router = APIRouter(prefix="/api/health", tags=["health"])
_client = docker.from_env()

SERVICES = [
    "takdb", "takserver_config", "takserver_messaging",
    "takserver_api", "takserver_retention", "takserver_pluginmanager",
    "pkg_server", "admin",
]


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
async def get_health():
    loop = asyncio.get_event_loop()
    states = await loop.run_in_executor(None, _get_states)
    return {"services": states}


@router.websocket("/stream")
async def health_stream(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            loop = asyncio.get_event_loop()
            states = await loop.run_in_executor(None, _get_states)
            await ws.send_text(json.dumps({"services": states}))
            await asyncio.sleep(5)
    except WebSocketDisconnect:
        pass
