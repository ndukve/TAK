# 08 — Backups

## What gets backed up

```bash
./backup.sh [output-dir]   # defaults to backups/<timestamp>/
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
./restore.sh <backup-dir>
```

**Destructive.** Overwrites the current admin DB, TAK CoT DB, certs/packages, plugins, and maps with the backup's data. Requires typing `restore` to confirm.

> Double-check `<backup-dir>` before restoring — the script only validates that `admin_db.sql` exists as a minimal sanity check, not full content consistency.

## When to back up

- Before `./update.sh` on a production deployment.
- Before changing `TAKSERVER_CERT_PASS`/`CA_PASS` (see [05-certificates-and-security.md](05-certificates-and-security.md)) — after a volume wipe there's nothing to restore from if you didn't back up first.
- On a regular schedule if this deployment is production — this repo doesn't ship a scheduled (`cron`) backup; you'd set that up yourself.
