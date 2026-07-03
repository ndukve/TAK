import asyncio
import json
import os
import socket
import time
from datetime import datetime
import docker
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, Query
from docker.errors import DockerException
from jose import JWTError, jwt
from cryptography import x509

from .deps import require_role, SECRET_KEY, ALGORITHM

router = APIRouter(prefix="/api/health", tags=["health"])
_client = docker.from_env()

SERVICES = [
    "takdb", "takserver_config", "takserver_messaging",
    "takserver_api", "takserver_retention", "takserver_pluginmanager",
    "admin",
]

CERT_PATHS = [
    ("root-ca", "/opt/tak/data/certs/files/root-ca.pem"),
    ("takserver", "/opt/tak/data/certs/files/takserver.pem"),
    ("admin-proxy-tls", "/etc/nginx-ssl/cert.pem"),
]

DISK_PATH = "/opt/tak/data"
HOST_PROC = "/host/proc"

_last_net = None  # (timestamp, rx_bytes, tx_bytes) — None until second sample
_last_cpu = None  # (total_jiffies, idle_jiffies) — None until second sample


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
            matches = _client.containers.list(
                all=True,
                filters={"label": f"com.docker.compose.service={name}"},
            )
            if matches:
                c = matches[0]
                out.append({"name": name, "status": c.status, "health": c.attrs.get("State", {}).get("Health", {}).get("Status", "none")})
            else:
                out.append({"name": name, "status": "not_found", "health": "none"})
        except DockerException:
            out.append({"name": name, "status": "not_found", "health": "none"})

    try:
        with socket.create_connection(("takserver_config", 8089), timeout=2):
            out.append({"name": "takserver_config:8089", "status": "running", "health": "none"})
    except OSError:
        out.append({"name": "takserver_config:8089", "status": "not_found", "health": "none"})

    return out


def _get_cpu_percent() -> float | None:
    global _last_cpu
    with open("/proc/stat") as f:
        parts = f.readline().split()
    values = [int(x) for x in parts[1:]]
    idle = values[3] + values[4]  # idle + iowait
    total = sum(values)

    if _last_cpu is None:
        _last_cpu = (total, idle)
        return None
    prev_total, prev_idle = _last_cpu
    _last_cpu = (total, idle)
    total_delta = total - prev_total
    idle_delta = idle - prev_idle
    if total_delta <= 0:
        return None
    return round((1 - idle_delta / total_delta) * 100, 1)


def _get_memory() -> tuple[int, int]:
    total_kb = avail_kb = 0
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                total_kb = int(line.split()[1])
            elif line.startswith("MemAvailable:"):
                avail_kb = int(line.split()[1])
    return (total_kb - avail_kb) // 1024, total_kb // 1024


def _get_uptime_seconds() -> int:
    with open("/proc/uptime") as f:
        return int(float(f.readline().split()[0]))


def _get_load_avg() -> list[float]:
    with open("/proc/loadavg") as f:
        parts = f.readline().split()
    return [float(parts[0]), float(parts[1]), float(parts[2])]


def _get_disk_usage() -> dict:
    st = os.statvfs(DISK_PATH)
    total = st.f_blocks * st.f_frsize
    free = st.f_bfree * st.f_frsize
    used = total - free
    return {
        "disk_used_gb": round(used / (1024 ** 3), 1),
        "disk_total_gb": round(total / (1024 ** 3), 1),
    }


def _read_net_bytes() -> tuple[int, int] | None:
    path = f"{HOST_PROC}/net/dev"
    if not os.path.isfile(path):
        return None
    rx_total = tx_total = 0
    with open(path) as f:
        lines = f.readlines()[2:]  # skip the 2 header lines
    for line in lines:
        iface, rest = line.split(":", 1)
        if iface.strip() == "lo":
            continue
        fields = rest.split()
        rx_total += int(fields[0])
        tx_total += int(fields[8])
    return rx_total, tx_total


def _get_network_rate() -> tuple[float | None, float | None]:
    global _last_net
    sample = _read_net_bytes()
    if sample is None:
        return None, None
    rx, tx = sample
    now = time.time()
    if _last_net is None:
        _last_net = (now, rx, tx)
        return None, None
    prev_time, prev_rx, prev_tx = _last_net
    _last_net = (now, rx, tx)
    dt = now - prev_time
    if dt <= 0:
        return None, None
    return round((rx - prev_rx) / dt, 0), round((tx - prev_tx) / dt, 0)


def _get_cert_expirations() -> list[dict]:
    out = []
    for name, path in CERT_PATHS:
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "rb") as f:
                cert = x509.load_pem_x509_certificate(f.read())
            expires_at = cert.not_valid_after
            days_remaining = (expires_at - datetime.utcnow()).days
            out.append({
                "name": name,
                "expires_at": expires_at.date().isoformat(),
                "days_remaining": days_remaining,
            })
        except Exception:
            continue
    return out


def _get_system_stats() -> dict:
    used_mb, total_mb = _get_memory()
    disk = _get_disk_usage()
    net_rx, net_tx = _get_network_rate()
    return {
        "cpu_percent": _get_cpu_percent(),
        "mem_used_mb": used_mb,
        "mem_total_mb": total_mb,
        "disk_used_gb": disk["disk_used_gb"],
        "disk_total_gb": disk["disk_total_gb"],
        "uptime_seconds": _get_uptime_seconds(),
        "load_avg": _get_load_avg(),
        "net_rx_bytes_per_sec": net_rx,
        "net_tx_bytes_per_sec": net_tx,
        "certs": _get_cert_expirations(),
    }


@router.get("")
async def get_health(_=Depends(require_role("admin", "superadmin"))):
    loop = asyncio.get_running_loop()
    states = await loop.run_in_executor(None, _get_states)
    system = await loop.run_in_executor(None, _get_system_stats)
    return {"services": states, "system": system}


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
            system = await loop.run_in_executor(None, _get_system_stats)
            await ws.send_text(json.dumps({"services": states, "system": system}))
            await asyncio.sleep(5)
    except WebSocketDisconnect:
        pass
