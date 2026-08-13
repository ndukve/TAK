<div align="center">

<img src="https://raw.githubusercontent.com/ndukve/TAK/main/docs/branding/logo-placeholder.svg" width="120" alt="TAK Server logo placeholder">

# TAK Server

Production-style deployment of the official Java TAK Server 5.7, containerized with docker compose, integrated with NetBird for secure overlay networking and managed from the WebUI.

[![TAK Server](https://img.shields.io/badge/TAK_Server-5.7-blue)](https://tak.gov/)
[![Debian](https://img.shields.io/badge/Debian-13_trixie-A81D33?logo=debian&logoColor=white)](https://www.debian.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![FastAPI](https://img.shields.io/badge/FastAPI-admin_API-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![React](https://img.shields.io/badge/React-admin_UI-61DAFB?logo=react&logoColor=black)](https://react.dev/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-PostGIS-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)

[![shellcheck](https://img.shields.io/github/actions/workflow/status/ndukve/TAK/shellcheck.yml?branch=main&label=shellcheck&logo=github&logoColor=white)](https://github.com/ndukve/TAK/actions/workflows/shellcheck.yml)
[![python-lint](https://img.shields.io/github/actions/workflow/status/ndukve/TAK/python-lint.yml?branch=main&label=python-lint&logo=github&logoColor=white)](https://github.com/ndukve/TAK/actions/workflows/python-lint.yml)
[![python-tests](https://img.shields.io/github/actions/workflow/status/ndukve/TAK/python-tests.yml?branch=main&label=python-tests&logo=github&logoColor=white)](https://github.com/ndukve/TAK/actions/workflows/python-tests.yml)
[![ui-checks](https://img.shields.io/github/actions/workflow/status/ndukve/TAK/ui-checks.yml?branch=main&label=ui-checks&logo=github&logoColor=white)](https://github.com/ndukve/TAK/actions/workflows/ui-checks.yml)
[![compose-validate](https://img.shields.io/github/actions/workflow/status/ndukve/TAK/compose-validate.yml?branch=main&label=compose-validate&logo=github&logoColor=white)](https://github.com/ndukve/TAK/actions/workflows/compose-validate.yml)
[![release](https://img.shields.io/github/actions/workflow/status/ndukve/TAK/release.yml?label=release&logo=github&logoColor=white)](https://github.com/ndukve/TAK/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/ndukve/TAK?include_prereleases&sort=semver&logo=github&logoColor=white)](https://github.com/ndukve/TAK/releases)

</div>

## Overview

```mermaid
flowchart LR
  subgraph clients [Clients]
    ATAK["ATAK / WinTAK / iTAK"]
  end
  subgraph server [TAK server]
    TAK["TAK Server\n8089 CoT · 8443 Marti API"]
    Admin["Admin panel\n8889"]
    DB[("PostgreSQL + PostGIS")]
  end
  clients -->|mTLS| TAK
  clients -->|HTTPS package download| Admin
  TAK --> DB
  Admin --> TAK
```

This repo holds a self-contained deployment: the official TAK Server binary, a custom admin panel for day-to-day operation, and the scripts that install/update/back up the whole stack. Configuration lives in `takserver.env` on the server itself — there's no GitOps sync layer, changes are applied by running the scripts below.

## Key components

| Area | Components |
|---|---|
| TAK core | `takserver_config` (CoT + Marti API), `takserver_messaging`, `takserver_api`, `takserver_retention`, `takserver_pluginmanager` |
| Data | `takdb` — PostgreSQL 15 + PostGIS, CoT and mission data |
| Admin panel | `admin` (FastAPI) behind `admin_proxy` (TLS reverse proxy), React + Vite UI |
| Isolation | `docker_socket_proxy` — the only path from the admin panel to Docker, restricted to logs/exec |
| Networking | NetBird, Tailscale, or plain LAN (operator's choice at install time) |
| Auth | Mutual TLS for clients; JWT + role-based access (`superadmin`/`admin`/`readonly`/`field`) for the admin panel, with optional OIDC SSO |

Client onboarding uses mutual TLS. Each user gets a signed certificate bundled into a TAK data package (`.zip`) containing server config, trust anchor, and ATAK preference defaults, downloaded through the admin panel and imported directly into the TAK client.

## Start here

1. [docs/README.md](docs/README.md) — full operator manual index (architecture, day-to-day ops, backups, troubleshooting, EN/LT).
2. [docs/INSTALL.md](docs/INSTALL.md) (EN) / [docs/DIEGIMAS.md](docs/DIEGIMAS.md) (LT) — step-by-step installation.
3. [docs/01-architecture.md](docs/01-architecture.md) — how the pieces fit together.
4. [docs/11-technical-reference.md](docs/11-technical-reference.md) — ports, env vars, `make` commands, roles, at a glance.

## Networking

Chosen during install — one of three, not NetBird-only:

- **NetBird** or **Tailscale** — WireGuard-based overlay for remote devices, no public ports required.
- **Plain LAN** — devices on the same network as the server use its local IP directly, no VPN.

Details: [docs/06-network-and-access.md](docs/06-network-and-access.md).

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8089 | TCP/TLS | CoT — primary TAK client input |
| 8443 | HTTPS | Marti API |
| 8087 | TCP | Internal CoT for service accounts, overlay network only — not for public exposure |
| 8889 | HTTPS | Admin panel — WebUI and authenticated package/plugin/map downloads |
| 9000–9002 | TCP/TLS | Federation (server-to-server) |

Full breakdown: [docs/11-technical-reference.md](docs/11-technical-reference.md).

## Repository Layout

```
Dockerfile                  TAK Server image
docker-compose.yml          Production stack
install.sh                  Interactive installer (Docker + VPN + config)
users.sh                    User/package management (create, purge, get)
scripts/
  firstrun.sh               PKI bootstrap + DB schema init
  start-tak.sh              Service entrypoint
  make_client_zip.sh        Builds client data package
  enable_user.sh            Registers cert with UserManager
templates/
  CoreConfig.tpl            TAK server config template (gomplate)
  missionpkg/               Client data package templates
```

Full layout, including `admin/` and `docs/`: [docs/02-repo-structure.md](docs/02-repo-structure.md).

## Operations

```bash
make status          # service health + listening ports
make logs            # follow all logs
make shell           # bash into config container
make add-user USERNAME=alice
make update          # pull latest, rebuild, restart
```
