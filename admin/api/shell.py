import asyncio
import socket

import docker
from docker.errors import DockerException
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect
from sqlalchemy import select

from .auth import consume_shell_ticket
from .db import SessionLocal
from .models import AdminUser

router = APIRouter(tags=["shell"])
_client = docker.from_env()
_SERVICE = "takserver_config"
_SESSION_MAX_SECONDS = 5 * 60


@router.websocket("/api/shell/ws")
async def shell_ws(ws: WebSocket, t: str = Query(...)):
    user_id = consume_shell_ticket(t)
    if not user_id:
        await ws.close(code=4001)
        return

    async with SessionLocal() as db:
        result = await db.execute(select(AdminUser).where(
            AdminUser.id == user_id,
            AdminUser.is_active,
            AdminUser.role == "superadmin",
            AdminUser.auth_provider == "local",
        ))
        if result.scalar_one_or_none() is None:
            await ws.close(code=4001)
            return

    await ws.accept()

    loop = asyncio.get_running_loop()
    try:
        exec_id = _client.api.exec_create(
            _SERVICE,
            ["/bin/bash"],
            stdin=True, stdout=True, stderr=True, tty=True,
        )
        sock = _client.api.exec_start(exec_id["Id"], socket=True, tty=True)
    except DockerException as e:
        await ws.send_text(f"[error] {e}\r\n")
        await ws.close()
        return
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
    done, _pending = await asyncio.wait(
        {container_task, client_task},
        timeout=_SESSION_MAX_SECONDS,
        return_when=asyncio.FIRST_COMPLETED,
    )
    if not done:
        try:
            await ws.send_text("\r\n[session expired — re-authentication required]\r\n")
        except Exception:
            pass

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
