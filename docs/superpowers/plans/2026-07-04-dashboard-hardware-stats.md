# Dashboard Hardware Stats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the admin Dashboard with host-level hardware stats (CPU, RAM, disk, uptime, load average, network throughput), certificate expiry tracking, and a TAK CoT port-8089 liveness check — all read-only.

**Architecture:** Backend collects everything from `/proc` (host-visible by default in this container), one bind-mounted host `/proc` for network stats specifically, and the already-mounted cert/admin-proxy-cert paths. Frontend adds two new small components to the existing Dashboard page, consuming an extended `GET /api/health` response.

**Tech Stack:** FastAPI (`admin/api/health.py`), Python stdlib (`os`, `socket`, `time`) + `cryptography.x509` (already a transitive dependency via `python-jose[cryptography]`), React + TanStack Router (`admin/ui/src/routes/index.tsx`).

## Global Constraints

- No automated test framework in this repo — verification is `python3 -c "import ast; ast.parse(...)"` for backend syntax and `npm run type-check` for frontend, plus a manual check on the deployed dashboard.
- Thresholds are hardcoded, not configurable: disk warns at 85% used, critical at 95%; certs warn under 30 days remaining, critical under 7.
- No background poller, no alerting channel (email/SMS) — this is read-only, in-page-only visibility.
- Never commit — stage with `git add <exact files>` and stop. The user commits everything themselves.

---

### Task 1: Backend — system stats collection + docker-compose mounts

**Files:**
- Modify: `docker-compose.yml` (admin service volumes)
- Modify: `admin/api/health.py` (full rewrite)

**Interfaces:**
- Produces: `GET /api/health` and `/api/health/stream` both now return `{"services": [...], "system": {...}}` — the `system` object's exact shape is consumed by Task 2's frontend types.

- [ ] **Step 1: Add the two new mounts to the `admin` service**

In `docker-compose.yml`, find the `admin` service's `volumes:` block:

```yaml
    volumes:
      - takserver_data:/opt/tak/data:rw
      - tak_plugins:/opt/tak/plugins:rw
      - ./packages/tak-maps:/opt/tak/maps:rw
```

Replace with:

```yaml
    volumes:
      - takserver_data:/opt/tak/data:rw
      - tak_plugins:/opt/tak/plugins:rw
      - ./packages/tak-maps:/opt/tak/maps:rw
      - /proc:/host/proc:ro
      - admin_ssl:/etc/nginx-ssl:ro
```

(`admin_ssl` is an existing named volume already declared at the bottom of this file and already mounted into `admin_proxy` at `/etc/nginx/ssl` — this adds a second, read-only mount of that same volume into `admin` at a different path, `/etc/nginx-ssl`, purely so the admin API can read the cert's expiry date.)

- [ ] **Step 2: Verify the compose file is still valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" && echo "docker-compose.yml valid"
```

Expected: prints `docker-compose.yml valid`.

- [ ] **Step 3: Replace `admin/api/health.py` in full**

```python
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
```

This replaces the file entirely — note it also drops `"pkg_server"` from `SERVICES` (dead now that the container no longer exists) and adds the `takserver_config:8089` liveness entry to the same list `_get_states()` returns.

- [ ] **Step 4: Verify backend syntax**

```bash
python3 -c "import ast; ast.parse(open('admin/api/health.py').read())" && echo "health.py OK"
```

Expected: prints `health.py OK`.

- [ ] **Step 5: Stage (do NOT commit)**

```bash
git add docker-compose.yml admin/api/health.py
```

---

### Task 2: Frontend — System stat cards + certificate list on the Dashboard

**Files:**
- Modify: `admin/ui/src/routes/index.tsx` (full rewrite)

**Interfaces:**
- Consumes: `GET /api/health`'s `system` object, exact shape produced by Task 1: `{cpu_percent: number|null, mem_used_mb: number, mem_total_mb: number, disk_used_gb: number, disk_total_gb: number, uptime_seconds: number, load_avg: [number,number,number], net_rx_bytes_per_sec: number|null, net_tx_bytes_per_sec: number|null, certs: {name: string, expires_at: string, days_remaining: number}[]}`.

- [ ] **Step 1: Replace `admin/ui/src/routes/index.tsx` in full**

```tsx
import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { CheckCircle, XCircle } from 'lucide-react'
import { cn } from '@/lib/utils'

export const Route = createFileRoute('/')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role === 'field') throw redirect({ to: '/packages' })
  },
  component: DashboardPage,
})

interface ServiceState {
  name: string
  status: string
  health: string
}

interface CertInfo {
  name: string
  expires_at: string
  days_remaining: number
}

interface SystemStats {
  cpu_percent: number | null
  mem_used_mb: number
  mem_total_mb: number
  disk_used_gb: number
  disk_total_gb: number
  uptime_seconds: number
  load_avg: [number, number, number]
  net_rx_bytes_per_sec: number | null
  net_tx_bytes_per_sec: number | null
  certs: CertInfo[]
}

function formatUptime(seconds: number): string {
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

function formatBytesPerSec(bytes: number | null): string {
  if (bytes === null) return '—'
  if (bytes < 1024) return `${bytes.toFixed(0)} B/s`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB/s`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB/s`
}

function DashboardPage() {
  const [services, setServices] = useState<ServiceState[]>([])
  const [system, setSystem] = useState<SystemStats | null>(null)

  async function load() {
    try {
      const data = await apiJson<{ services: ServiceState[]; system: SystemStats }>('/api/health')
      setServices(data.services)
      setSystem(data.system)
    } catch {}
  }

  useEffect(() => {
    load()
    const id = setInterval(load, 5000)
    return () => clearInterval(id)
  }, [])

  const diskPercent = system ? (system.disk_used_gb / system.disk_total_gb) * 100 : 0
  const diskState = diskPercent >= 95 ? 'critical' : diskPercent >= 85 ? 'warn' : 'ok'

  return (
    <Layout>
      <div className="p-6">
        <h1 className="text-xl font-semibold mb-6">Dashboard</h1>

        {system && (
          <>
            <div className="grid grid-cols-2 lg:grid-cols-6 gap-4 mb-6">
              <SystemStatCard label="CPU" value={system.cpu_percent !== null ? `${system.cpu_percent}%` : '—'} />
              <SystemStatCard label="RAM" value={`${(system.mem_used_mb / 1024).toFixed(1)} / ${(system.mem_total_mb / 1024).toFixed(1)} GB`} />
              <SystemStatCard label="Disk" value={`${system.disk_used_gb.toFixed(1)} / ${system.disk_total_gb.toFixed(1)} GB`} state={diskState} />
              <SystemStatCard label="Uptime" value={formatUptime(system.uptime_seconds)} />
              <SystemStatCard label="Load avg" value={system.load_avg.map(n => n.toFixed(2)).join(' / ')} />
              <SystemStatCard label="Network" value={`↓${formatBytesPerSec(system.net_rx_bytes_per_sec)} ↑${formatBytesPerSec(system.net_tx_bytes_per_sec)}`} />
            </div>
            <CertList certs={system.certs} />
          </>
        )}

        <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-3">Services</h2>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {services.map(s => (
            <ServiceCard key={s.name} service={s} />
          ))}
        </div>
      </div>
    </Layout>
  )
}

function SystemStatCard({ label, value, state = 'ok' }: { label: string; value: string; state?: 'ok' | 'warn' | 'critical' }) {
  const badgeClass = state === 'critical' ? 'border-red-800 bg-red-500/10' : state === 'warn' ? 'border-yellow-800 bg-yellow-500/10' : 'border-zinc-700 bg-zinc-800/50'
  const textClass = state === 'critical' ? 'text-red-400' : state === 'warn' ? 'text-yellow-400' : 'text-zinc-200'
  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <div className="flex items-start justify-between mb-3">
        <span className="text-[10px] font-semibold tracking-wider text-zinc-500 uppercase">{label}</span>
        <div className={cn('w-7 h-7 rounded-md border shrink-0', badgeClass)} />
      </div>
      <p className={cn('text-sm font-medium font-mono', textClass)}>{value}</p>
    </div>
  )
}

function CertList({ certs }: { certs: CertInfo[] }) {
  if (certs.length === 0) return null
  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4 mb-6">
      <span className="text-[10px] font-semibold tracking-wider text-zinc-500 uppercase">Certificates</span>
      <div className="mt-3 space-y-2">
        {certs.map(c => {
          const state = c.days_remaining < 7 ? 'critical' : c.days_remaining < 30 ? 'warn' : 'ok'
          const textClass = state === 'critical' ? 'text-red-400' : state === 'warn' ? 'text-yellow-400' : 'text-green-400'
          return (
            <div key={c.name} className="flex items-center justify-between text-sm">
              <span className="font-mono text-zinc-300">{c.name}</span>
              <span className="text-zinc-500">{c.expires_at}</span>
              <span className={cn('font-mono text-xs', textClass)}>{c.days_remaining}d remaining</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}

function ServiceCard({ service }: { service: ServiceState }) {
  const running = service.status === 'running'
  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <div className="flex items-start justify-between mb-3">
        <span className="text-[10px] font-semibold tracking-wider text-zinc-500 uppercase">Service</span>
        <div className={cn(
          'w-7 h-7 rounded-md border flex items-center justify-center shrink-0',
          running ? 'border-green-800 bg-green-500/10' : 'border-red-800 bg-red-500/10'
        )}>
          {running
            ? <CheckCircle size={14} className="text-green-500" />
            : <XCircle size={14} className="text-red-500" />
          }
        </div>
      </div>
      <p className="text-sm font-medium text-zinc-200 font-mono mb-2">{service.name}</p>
      <div className="border-t border-zinc-800 pt-2">
        <span className={cn('text-xs font-medium', running ? 'text-green-400' : 'text-red-400')}>
          {service.status}
        </span>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Type-check**

```bash
cd admin/ui && npm run type-check
```

Expected: clean (no errors).

- [ ] **Step 3: Stage (do NOT commit)**

```bash
git add admin/ui/src/routes/index.tsx
```

---

### Task 3: Manual end-to-end verification

**Files:** none — verification only.

- [ ] **Step 1: Deploy**

Commit, push, then on the server: `sudo ./update.sh`.

- [ ] **Step 2: Confirm the API shape**

```bash
curl -k -X POST https://localhost:8889/auth/login -H "Content-Type: application/json" -d '{"username":"admin","password":"<your password>"}'
# copy the access_token from the response, then:
curl -k https://localhost:8889/api/health -H "Authorization: Bearer <access_token>"
```

Expected: JSON with both `services` (including a `takserver_config:8089` entry) and `system` (all fields populated; `cpu_percent`/`net_*_bytes_per_sec` will be `null` on the very first call after a restart — that's expected, they need two samples).

- [ ] **Step 3: Visual check on the Dashboard**

Load the Dashboard in a browser. Confirm: 6 stat cards render (CPU/RAM/Disk/Uptime/Load avg/Network) with sensible values, a Certificates card lists the 3 tracked certs with plausible expiry dates, and the Services grid below still renders correctly including the new `takserver_config:8089` entry.

---
