import asyncio
import docker
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from docker.errors import DockerException
from .auth import consume_shell_ticket

router = APIRouter(tags=["shell"])
_client = docker.from_env()
CONTAINER_NAME = "takserver_config"


@router.websocket("/api/shell/ws")
async def shell_ws(ws: WebSocket, t: str = Query(...)):
    user_id = consume_shell_ticket(t)
    if not user_id:
        await ws.close(code=4001)
        return

    await ws.accept()

    loop = asyncio.get_running_loop()
    try:
        container = _client.containers.get(CONTAINER_NAME)
    except DockerException as e:
        await ws.send_text(f"[error] {e}\r\n")
        await ws.close()
        return

    exec_id = container.client.api.exec_create(
        container.id,
        ["/bin/bash"],
        stdin=True, stdout=True, stderr=True, tty=True,
    )
    sock = container.client.api.exec_start(exec_id["Id"], socket=True, tty=True)
    raw_sock = sock._sock

    raw_sock.setblocking(False)

    async def read_container():
        while True:
            try:
                data = await loop.run_in_executor(None, raw_sock.recv, 4096)
                if not data:
                    break
                await ws.send_bytes(data)
            except Exception:
                break

    async def read_client():
        while True:
            try:
                msg = await ws.receive()
                if "bytes" in msg:
                    await loop.run_in_executor(None, raw_sock.sendall, msg["bytes"])
                elif "text" in msg:
                    await loop.run_in_executor(None, raw_sock.sendall, msg["text"].encode())
            except WebSocketDisconnect:
                break
            except Exception:
                break

    await asyncio.gather(read_container(), read_client())

    try:
        raw_sock.close()
    except Exception:
        pass
