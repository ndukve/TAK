import asyncio
import socket

import docker
from docker.errors import DockerException
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from .auth import consume_shell_ticket

router = APIRouter(tags=["shell"])
_client = docker.from_env()
_SERVICE = "takserver_config"


def _get_container():
    matches = _client.containers.list(filters={"label": f"com.docker.compose.service={_SERVICE}"})
    if not matches:
        raise DockerException(f"No running container for service '{_SERVICE}'")
    return matches[0]


@router.websocket("/api/shell/ws")
async def shell_ws(ws: WebSocket, t: str = Query(...)):
    user_id = consume_shell_ticket(t)
    if not user_id:
        await ws.close(code=4001)
        return

    await ws.accept()

    loop = asyncio.get_running_loop()
    try:
        container = _get_container()
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

    # Must stay blocking — recv()/sendall() run inside run_in_executor threads,
    # which is the correct way to do blocking I/O from asyncio. A non-blocking
    # socket makes recv() raise BlockingIOError almost immediately (no data is
    # ever queued yet), which the except-clause below silently treats as EOF —
    # killing the container output loop right after connecting.

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

    container_task = asyncio.create_task(read_container())
    client_task = asyncio.create_task(read_client())

    # Whichever side finishes first (e.g. the browser tab closes while the
    # shell is idle at a bash prompt), close the socket immediately instead
    # of waiting for both — recv() on an idle socket never returns on its
    # own, which used to leak a thread from the shared default executor
    # forever per abandoned session, eventually starving every other admin
    # operation that runs through that same executor.
    await asyncio.wait({container_task, client_task}, return_when=asyncio.FIRST_COMPLETED)

    try:
        raw_sock.shutdown(socket.SHUT_RDWR)
    except Exception:
        pass
    try:
        raw_sock.close()
    except Exception:
        pass

    for task in (container_task, client_task):
        if not task.done():
            task.cancel()
    await asyncio.gather(container_task, client_task, return_exceptions=True)
