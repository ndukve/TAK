import asyncio
import docker
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from docker.errors import DockerException
from jose import JWTError, jwt

from .deps import SECRET_KEY, ALGORITHM

router = APIRouter(tags=["logs"])
_client = docker.from_env()

ALLOWED_SERVICES = {
    "takdb", "takserver_config", "takserver_messaging",
    "takserver_api", "takserver_retention", "takserver_pluginmanager",
    "pkg_server", "admin",
}


def _verify_ws_token(token: str) -> bool:
    """Validate JWT before accepting WebSocket. Returns True if valid admin/superadmin."""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload.get("role") in ("admin", "superadmin")
    except JWTError:
        return False


@router.websocket("/api/logs")
async def log_stream(ws: WebSocket, service: str = Query(...), token: str = Query(...)):
    if not _verify_ws_token(token):
        await ws.close(code=4401)
        return

    if service not in ALLOWED_SERVICES:
        await ws.accept()
        await ws.send_text(f"[error] Unknown service: {service}")
        await ws.close()
        return

    await ws.accept()

    try:
        container = _client.containers.get(service)
    except DockerException as e:
        await ws.send_text(f"[error] {e}")
        await ws.close()
        return

    log_gen = container.logs(stream=True, follow=True, tail=100)
    loop = asyncio.get_running_loop()
    try:
        while True:
            line = await loop.run_in_executor(None, next, log_gen, None)
            if line is None:
                break
            await ws.send_text(line.decode("utf-8", errors="replace").rstrip())
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        log_gen.close()
