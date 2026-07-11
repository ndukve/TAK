import asyncio
import json
import os
import ssl
import time

CERT_DIR = "/opt/tak/data/certs/files"
DISK_PATH = "/opt/tak/data"


async def _open_cot_connection(cert_path: str, key_path: str, key_password: str, server_addr: str):
    """Open a TLS connection to the TAK server's CoT port using the service
    client cert. Isolated in its own function so tests (and live_map.py) can
    monkeypatch it without a real TAK server."""
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_ctx.load_cert_chain(certfile=cert_path, keyfile=key_path, password=key_password)
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE
    reader, writer = await asyncio.open_connection(server_addr, 8089, ssl=ssl_ctx)
    return reader, writer


class ReplayRecorder:
    """Records CoT events from the TAK server to time-windowed NDJSON chunk
    files. One instance lives for the lifetime of the admin API process
    (created once in replay.py), started/stopped on demand."""

    def __init__(self, chunk_dir: str, server_addr: str):
        self.chunk_dir = chunk_dir
        self.server_addr = server_addr
        self._task: asyncio.Task | None = None
        self._stop_event = asyncio.Event()
        self._current_chunk_id: str | None = None
        self._reader = None
        self._writer = None

    def is_recording(self) -> bool:
        return self._task is not None and not self._task.done()

    def current_chunk_id(self) -> str | None:
        return self._current_chunk_id

    async def start(self, chunk_id: str, cert_path: str, key_path: str, key_password: str) -> None:
        if self.is_recording():
            raise RuntimeError("Already recording")
        os.makedirs(self.chunk_dir, exist_ok=True)
        self._current_chunk_id = chunk_id
        self._stop_event = asyncio.Event()
        self._reader, self._writer = await _open_cot_connection(cert_path, key_path, key_password, self.server_addr)
        self._task = asyncio.ensure_future(self._record_loop(chunk_id))

    async def stop(self) -> tuple[int, int]:
        """Returns (event_count, size_bytes) for the finalized chunk."""
        if not self.is_recording():
            return 0, 0
        self._stop_event.set()
        if self._writer:
            self._writer.close()
        await self._task
        chunk_id = self._current_chunk_id
        self._current_chunk_id = None
        self._task = None
        path = os.path.join(self.chunk_dir, f"{chunk_id}.ndjson")
        event_count = 0
        size_bytes = 0
        if os.path.isfile(path):
            with open(path) as f:
                event_count = sum(1 for _ in f)
            size_bytes = os.path.getsize(path)
        return event_count, size_bytes

    async def _record_loop(self, chunk_id: str) -> None:
        path = os.path.join(self.chunk_dir, f"{chunk_id}.ndjson")
        with open(path, "a") as f:
            while not self._stop_event.is_set():
                try:
                    data = await asyncio.wait_for(self._reader.read(65536), timeout=1.0)
                except TimeoutError:
                    continue
                if not data:
                    break
                line = json.dumps({"ts": int(time.time() * 1000), "raw_cot": data.decode("utf-8", errors="replace")})
                f.write(line + "\n")
                f.flush()


class ReplayPlayer:
    """Re-injects a recorded chunk's CoT events back into the TAK server,
    preserving original relative timing scaled by `speed`."""

    def __init__(self, server_addr: str):
        self.server_addr = server_addr
        self._task: asyncio.Task | None = None
        self._writer = None

    def is_playing(self) -> bool:
        return self._task is not None and not self._task.done()

    async def start(self, chunk_path: str, speed: float, cert_path: str, key_path: str, key_password: str) -> None:
        if self.is_playing():
            raise RuntimeError("Already playing")
        _, self._writer = await _open_cot_connection(cert_path, key_path, key_password, self.server_addr)
        self._task = asyncio.ensure_future(self._play_loop(chunk_path, speed))

    async def stop(self) -> None:
        if not self.is_playing():
            return
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass
        if self._writer:
            self._writer.close()
        self._task = None

    async def _play_loop(self, chunk_path: str, speed: float) -> None:
        with open(chunk_path) as f:
            lines = [json.loads(line) for line in f if line.strip()]
        if not lines:
            return
        base_ts = lines[0]["ts"]
        start_time = time.time()
        for entry in lines:
            target_offset = (entry["ts"] - base_ts) / 1000.0 / speed
            elapsed = time.time() - start_time
            if target_offset > elapsed:
                await asyncio.sleep(target_offset - elapsed)
            self._writer.write(entry["raw_cot"].encode("utf-8"))
            await self._writer.drain()


def free_disk_mb(path: str = DISK_PATH) -> float:
    st = os.statvfs(path)
    return (st.f_bavail * st.f_frsize) / (1024 ** 2)
