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
| Live Map tiles show "Access blocked — App is not following the tile usage policy" (403) | Fetching OpenStreetMap tiles straight from the browser can't set a real User-Agent and can't be cached, both required by OSM's tile usage policy — heavy/anonymous use gets blocked | Fixed — tiles now proxy through `/api/live-map/tiles` (admin backend), which sets a real User-Agent and caches every tile to disk (`/tmp/tile-cache`) so repeat views never re-hit OpenStreetMap. Rebuild/redeploy `admin` if you're still seeing this |
| ATAK doesn't show other users' markers or EFDI sensor tracks by itself — everything shows up fine in WinTAK, or a marker only appears in ATAK after you manually "Send To" that one contact | The device's certificate isn't (or is no longer) a member of the shared `TAK-USERS` routing group — TAK Server only auto-broadcasts CoT between clients in the same group. A manual "Send To" bypasses group routing, which is why it still works. The server's live group-membership cache can also get stuck even for a device that was set up correctly | Run `./users.sh repair-groups` to reassign every packaged client to `TAK-USERS`. If markers still don't show up afterwards, the group-membership cache itself is likely wedged — a full restart clears it: `docker compose down && docker compose up -d` (takes the server offline briefly) |
| A drone's live position from its ground-control-station app never shows up in ATAK's UAS Tool | ATAK's UAS Tool only picks up a drone from MAVLink telemetry sent to it over UDP — the GCS app doesn't send it there unless configured to | In the GCS app, enable MAVLink forwarding (in QGroundControl-based apps: Settings → General → MAVLink → Forward Mavlink) to UDP port 14550, addressed to the ATAK device — `127.0.0.1` if the GCS app and ATAK run on the same device, otherwise the device's LAN or NetBird IP. ATAK's UAS Tool then shows the drone automatically, no import needed |
| Plugins list mixes ATAK, WinTAK, and iTAK builds together with no way to tell which is which at a glance | Old UI (fixed): plugin uploads had no app-type or version metadata | Upload now asks for the target app (ATAK/WinTAK/iTAK/Other) and a version; the Packages → Plugins list groups and sorts by app type automatically |
| WebUI re-skin edits to `admin/ui/src/styles/scout-tokens.css` (fonts, colors, radius) don't show up in the built app at all | `admin/ui/src/index.css` (the real entry point, imported *after* scout-tokens.css) redeclared its own `--color-hud-*`/`--font-*`/`--radius-*` tokens on top of it, silently overriding every value scout-tokens.css set | Fixed — the duplicate `@theme` block and self-hosted Inter/JetBrains `@font-face` rules were removed from `index.css`; scout-tokens.css is now the only place these tokens are declared. If you add a *new* competing token declaration in either file again, check both files, not just the one you edited |
| Buttons/focus rings/every shadcn "primary"-colored element render as unstyled/black instead of the theme's blue | `index.css`'s `--primary` fallback chain pointed at `var(--blue-600)`, a raw color variable that no longer exists after the old steel/blue Scout ramp was removed from scout-tokens.css — an invalid `var()` fallback makes the whole custom property invalid | Fixed — `--primary`/`--primary-foreground` are now declared once, in scout-tokens.css itself, falling back through the admin-configurable white-label accent (`--brand-accent-fill`, set by `store/branding.ts`) to a real literal color, never to a deleted variable |

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
