# Dashboard Hardware Stats — Design

## Purpose

The admin Dashboard (`admin/ui/src/routes/index.tsx`) currently shows only per-container status cards (running/not_found). Extend it with host-level hardware stats (CPU, RAM, disk, uptime, load average, network throughput), certificate expiry tracking, and a TAK CoT port liveness check — all read-only, all informational. This is the "hardware stats" half of a larger dashboard-elaboration request; the other half (letting the web UI trigger `update.sh`/`health.sh`/reinstall) is deliberately out of scope here and will get its own design later, since it requires a new host-execution channel with real security tradeoffs that don't belong in a read-only monitoring pass.

## Non-goals

- No triggering of scripts/actions from the dashboard (that's the deferred script-runner design).
- No background alerting channel (email/SMS) — thresholds only drive in-page color states, nothing gets pushed anywhere.
- No per-client-package cert expiry tracking — only the core server certs (CA, TAK server cert, admin-proxy TLS cert) are tracked.
- No configurable thresholds — the 85%/95% disk and 30/7-day cert thresholds are hardcoded sensible defaults.
- No OOM-cause attribution or a continuous background poller — Docker's own `restart: unless-stopped` already recovers crashed containers; this pass only adds visibility, not new recovery logic.

## Architecture

Docker does not namespace most of `/proc` by default — a container's own `/proc/stat`, `/proc/meminfo`, `/proc/loadavg`, and `/proc/uptime` already reflect the real host's numbers, not the container's. So CPU/RAM/load-average/uptime need no new mounts at all; the existing `admin` container already has host-accurate data available today.

Three things need something new, all read-only, all zero-write/zero-exec, none touching `docker_socket_proxy`'s deliberately narrow scope:

- **Network throughput**: `/proc/net/dev` *is* per-network-namespace (unlike the files above), so the container's own copy only shows its docker-bridge traffic. Fix: bind-mount host `/proc` read-only as `/host/proc` on the `admin` service in `docker-compose.yml`; read `/host/proc/net/dev` for this one stat.
- **Disk usage**: `os.statvfs()` on `/opt/tak/data`, which `admin` already has mounted (`docker-compose.yml:145`) — no new mount.
- **Certificate expiry**: `root-ca.pem`, `takserver.pem`, and the admin client cert already live under `/opt/tak/data/certs/files/` (already mounted). The admin-proxy's own TLS cert (`admin_ssl` volume) is currently only mounted into the `admin_proxy` (nginx) service — add a second, read-only mount of that same existing named volume into `admin`.
- **Port 8089 (TAK CoT) liveness**: plain TCP connect probe from `admin` to `takserver_config:8089` over the existing internal `taknet` docker network — no mount, no new permission, they're already on the same network.

Net result: exactly two new lines in `docker-compose.yml` (`/proc:/host/proc:ro` and a second read-only mount of `admin_ssl`) for the entire feature.

## API

Extend the existing `GET /api/health` response (and its `/api/health/stream` websocket sibling, both in `admin/api/health.py`) with a new `system` block alongside the existing `services` list:

```json
{
  "services": [...],
  "system": {
    "cpu_percent": 12.4,
    "mem_used_mb": 3102, "mem_total_mb": 7963,
    "disk_used_gb": 41.2, "disk_total_gb": 80.0,
    "uptime_seconds": 118440,
    "load_avg": [0.42, 0.51, 0.48],
    "net_rx_bytes_per_sec": 8213, "net_tx_bytes_per_sec": 1042,
    "certs": [
      {"name": "root-ca", "expires_at": "2034-02-01", "days_remaining": 2891},
      {"name": "takserver", "expires_at": "2027-11-03", "days_remaining": 487},
      {"name": "admin-proxy-tls", "expires_at": "2036-07-01", "days_remaining": 3650}
    ]
  }
}
```

Port 8089 liveness is folded into the existing `services` array as one more entry (same `{name, status, health}` shape the other services already use) rather than a separate field, since it's the same kind of information.

Network throughput needs two samples to compute a rate. The backend caches the last `(timestamp, rx_bytes, tx_bytes)` in a module-level variable and diffs on each call — this works on the existing plain-polling `GET /api/health` (already called every 5s by the dashboard) without requiring the frontend to switch onto the websocket variant.

**Thresholds (hardcoded):** disk usage warns at 85% used, critical at 95%. Cert expiry warns under 30 days remaining, critical under 7. These drive green/yellow/red color states on the stat cards — no new toast/notification system.

**Error handling:** if `/host/proc` isn't mounted yet (e.g. a deployment that hasn't run `docker compose up` since this shipped), the network-throughput read fails; the endpoint catches that specifically and reports `null` for just that field rather than failing the whole `/api/health` call. Same graceful-degrade if the admin-proxy cert mount isn't present yet.

## UI

New "System" section on the Dashboard (`admin/ui/src/routes/index.tsx`), above the existing service-status grid:

- A row of stat cards mirroring the existing `ServiceCard`'s visual style: **CPU%**, **RAM** (used/total), **Disk** (used/total, colored per threshold), **Uptime**, **Load avg** (1/5/15), **Network** (rx/tx per sec).
- A separate small **Certificates** card listing each tracked cert with its expiry date and a colored days-remaining badge.
- Port 8089 appears in the existing services grid as one more `ServiceCard` entry.

Same 5s polling cadence already in place, same mobile-responsive card-grid pattern already established elsewhere in this admin panel. New components: `SystemStatCard`, `CertList` — both simple and single-purpose, matching the existing file's structure.

## Related cleanup folded in

`admin/api/health.py`'s `SERVICES` list still includes `"pkg_server"` (line 14), which is dead now that the container no longer exists — it would otherwise show a permanent "not_found" card. Remove it from the list as part of this same plan, since it's the same file being touched.

## Testing

No automated test framework in this repo — verification is manual: `python3 -c "import ast; ast.parse(...)"` for backend syntax, `npm run type-check` for the frontend, and a manual check on the deployed dashboard that all new stat cards render sensible values and the color thresholds trigger correctly (can be forced by temporarily lowering a threshold during testing, then reverting).
