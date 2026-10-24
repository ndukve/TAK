# 08 — Backups

## What gets backed up

```bash
./scripts/backup.sh [output-dir]   # defaults to backups/<timestamp>/
```

- `admin_db.sql` — admin panel PostgreSQL dump (`pg_dump`)
- `cot_db.sql` — TAK CoT database dump
- `takserver_data.tar.gz` — certificates, packages, the contents of `/opt/tak/data`
- `tak_plugins.tar.gz` — server plugins
- `tak-maps.tar.gz` — map sources (if `packages/tak-maps/` exists)
- `takserver.env` — a copy of the config

All output files get `chmod 600` — they contain passwords and certificate keys.

## Restoring

```bash
./scripts/restore.sh <backup-dir>
```

**Destructive.** Overwrites the current admin DB, TAK CoT DB, certs/packages, plugins, and maps with the backup's data. Requires typing `restore` to confirm.

**Restoring onto a fresh install:** `restore.sh` does not restore `takserver.env`, but the restored certificates are encrypted with the old file's passwords. Before restoring, copy `CA_PASS`, `ADMIN_CERT_PASS`, `TAKSERVER_CERT_PASS` and `ADMIN_SECRET_KEY` from the backup's `takserver.env` into the new one (keep the new `POSTGRES_*` passwords; the new database has its own roles). The script now refuses to start when these four differ, before it overwrites anything. Afterwards run `docker compose --env-file takserver.env up -d --force-recreate`, not `make up`.

> Double-check `<backup-dir>` before restoring — the script only validates that `admin_db.sql` exists as a minimal sanity check, not full content consistency.

## When to back up

- Before `./scripts/update.sh` on a production deployment.
- Before changing `TAKSERVER_CERT_PASS`/`CA_PASS` (see [05-certificates-and-security.md](05-certificates-and-security.md)) — after a volume wipe there's nothing to restore from if you didn't back up first.
- On a regular schedule if this deployment is production — this repo doesn't ship a scheduled (`cron`) backup; you'd set that up yourself.

## Where the data lives (outside Docker)

Everything that must survive a reinstall is kept on the host, not in Docker volumes, under `TAK_DATA_DIR` in `takserver.env` (default `/srv/tak-data`):

| Directory | Holds |
|---|---|
| `takserver_data` | the CA and its key, the server and client certificates, the client packages |
| `tak_plugins`, `tak_plugin_conf` | the plugins served to clients and their configuration |
| `takdb_data` | the PostgreSQL data (CoT and admin databases) |

Images, containers and `/var/lib/docker` can be deleted, rebuilt or lost without touching these directories, and `install.sh` (Reinstall) and `update.sh` never remove them. A server that still has the old named volumes has them copied into `TAK_DATA_DIR` once by `update.sh` or `install.sh`; the old volumes are left in place until you remove them yourself, and a marker file `.migrated-<part>` stops the copy from ever running twice. `TAK_DATA_DIR` must not be inside `/var/lib/docker`.

Put `TAK_DATA_DIR` on its own disk or on the volume your VM backup covers. `backup.sh` archives these directories as root, because the CA key is readable only by the TAK user.
