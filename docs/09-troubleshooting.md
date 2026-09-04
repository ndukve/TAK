# 09 — Troubleshooting

## Always start here

```bash
./health.sh
```

Checks whether running images match the current `git` commit (a symptom of Docker layer-cache staleness — code changed on disk, but the container is still running the old build) and runs the package builder's self-test. Force-rebuilds (`--no-cache`) automatically if it finds a mismatch.

## Common symptoms

| Symptom | Cause | Fix |
|---|---|---|
| Client package download on `:8888` doesn't work | Port is stale in docs, not actually exposed | Use the admin panel (`:8889`, Packages → Download) or `./admin_fallback.sh` — see [06-network-and-access.md](06-network-and-access.md) |
| Clients/services stop connecting after changing `TAKSERVER_CERT_PASS`/`CA_PASS` | Old JKS in the volume, new password in the env — mismatch | Requires a volume wipe and cert regeneration, see [05-certificates-and-security.md](05-certificates-and-security.md) — back up **first** |
| A container action (e.g. generating a cert via the admin panel) returns `No such container: <name>` | `docker_socket_proxy` can't find the target container — either it's not running, or this is an isolated dev environment without the full TAK stack | `make status` to check the service is up; in a full deployment check `docker compose ps` |
| Code changed on disk, but the container still behaves like the old version | Docker layer-cache staleness | `./health.sh` (self-heal detects and fixes this automatically) |
| WebUI totally unreachable | Network/port issue, or the `admin`/`admin_proxy` service crashed | `make status`, `make logs`; if you just need to view/download packages — `./admin_fallback.sh` (terminal, read-only) |
| `update.sh` stops after the build | Self-test failed | `update.sh` calls `health.sh` automatically; if that still doesn't fix it, check the build logs manually with `docker compose build --progress plain` |
| Built an image (`docker compose build ...`) but don't see the change take effect | `build` alone doesn't recreate running containers — they keep running the old image until something restarts them | Use `make build` (chains into `make up` automatically) instead of a bare `docker compose build`; or follow any manual build with `docker compose up -d` |
| ATAK/WinTAK package downloads and imports, but the server never appears in the connections list | Old bug (fixed): generated packages referenced cert files at `cert/...` inside the zip, but they're actually stored under `content/...` — WinTAK's importer tolerated the mismatch, ATAK's didn't | Regenerate the package — current templates are correct. If it's still stale, rebuild `tak_permissions` (bakes `templates/` into `takserver:local`) and confirm the running `takserver_config` container is on the new image before regenerating |
| Tapping the package in ATAK's Local SD import does nothing at all (no toast, no error, checkbox+OK doesn't help either) | ATAK's own background file-watcher (used to notice imported files and actually process them) is known-unreliable on some Android versions/devices — the file just sits there, never extracted | Force-stop and relaunch ATAK first (its startup scan can pick up the missed file). If that doesn't work, clear ATAK's app cache **and storage data** (Android Settings → Apps → ATAK → Storage) — this has reliably fixed a stuck import in practice |
| Large map file (multi-GB `.mbtiles`) download button does nothing / appears to hang | The download buffered the entire file into a browser Blob before saving — stalls or looks hung on multi-GB files | Fixed — map downloads now stream via a one-time ticket + native browser download instead of a Blob. Make sure the `admin` container is rebuilt/redeployed (see the `make build` row above) |
| Live Map tiles show a big "API KEY REQUIRED" watermark instead of the map | Old CARTO tile provider now requires a paid API key | Fixed — tiles switched to key-free OpenStreetMap. Rebuild/redeploy `admin` if you're still seeing this |

## Logs

```bash
make logs        # all services
make logs-db     # takdb only
make status      # service status + listening ports
```

## When nothing works

1. Check that `takserver.env` exists and is complete (diff it against `takserver.env.example`).
2. Check the Docker Engine itself (`docker info`).
3. If the deployment is critical and time is short — restore the last backup ([08-backups.md](08-backups.md)) instead of continuing to debug a live system.
