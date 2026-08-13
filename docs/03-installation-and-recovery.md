# 03 — Installation and Recovery

This document is a high-level overview of when and how installation/recovery happens. Step-by-step instructions live in the dedicated guides.

## New installation

Full guide: [docs/INSTALL.md](INSTALL.md) (EN) / [docs/DIEGIMAS.md](DIEGIMAS.md) (LT).

`install.sh` is an interactive 7-step wizard:

| Step | Sets |
|---|---|
| 1/7 — Networking | How devices reach the server: NetBird, Tailscale, or a manual IP (see [06-network-and-access.md](06-network-and-access.md)) |
| 2/7 — Certificate metadata | CA details (country, organization, etc.) — see [05-certificates-and-security.md](05-certificates-and-security.md) |
| 3/7 — Admin panel | First superadmin username/password |
| 4/7 — Review | Confirm the summary before anything runs |
| 5/7 — System setup | Installs Docker Engine if it's missing |
| 6/7 — Write config | Generates `takserver.env` from your answers |
| 7/7 — Build & start | Builds images and starts containers |

When it's done, the script prints the CoT/API/admin panel addresses and the first admin login.

**Re-running on an existing install:** if `takserver.env` already exists, the script detects it and offers to leave it as-is or reconfigure (overwriting `takserver.env`).

## Offline installation

`install-offline.sh` — same wizard, but uses pre-fetched Docker images instead of `docker pull`. Useful for air-gapped networks.

## Restoring from a backup

Full procedure: [08-backups.md](08-backups.md).

Short version: `./restore.sh <backup-dir>` — **destructive**, overwrites the current admin DB, TAK CoT DB, certs/packages, plugins, and maps with the backup's data. Requires typing `restore` to confirm.

## Updating (not a fresh install)

Updating an already-running deployment to the latest code is **not** this document — see [10-updates.md](10-updates.md).
