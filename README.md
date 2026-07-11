<div align="center">

<img src="https://raw.githubusercontent.com/ndukve/TAK/main/docs/branding/logo-placeholder.svg" width="120" alt="TAK Server logo placeholder">

# TAK Server

Production-style deployment of the official Java TAK Server 5.7, containerized with docker compose, integrated with NetBird for secure overlay networking and managed from the WebUI.

[![TAK Server](https://img.shields.io/badge/TAK_Server-5.7-blue)](https://tak.gov/)
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

## Architecture

| Service | Role |
|---------|------|
| `takdb` | PostgreSQL 15 + PostGIS — persistent CoT and mission data |
| `takserver_initialization` | One-shot: generates PKI, initialises DB schema |
| `takserver_config` | Main process — SSL CoT on 8089, HTTPS API on 8443 |
| `takserver_messaging` | Handles real-time CoT routing |
| `takserver_api` | REST API for mission packages, data feeds |
| `takserver_retention` | Prunes stale data per retention policy |
| `takserver_pluginmanager` | Plugin lifecycle management |

Client onboarding uses mutual TLS. Each user gets a signed certificate bundled into a TAK data package (`.zip`) containing server config, trust anchor, and ATAK preference defaults. Packages are served over HTTP and imported directly into the TAK client.

## Networking

All client traffic runs over a NetBird WireGuard overlay (`wt0`). No ports need to be exposed to the public internet — devices connect to the server via their shared NetBird authentification.

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8089 | TCP/TLS | CoT — primary TAK client input |
| 8443 | HTTPS | Marti API |
| 8888 | HTTP | Client data package distribution |

## Repository Layout

```
Dockerfile                  TAK Server image
docker-compose.yml          Production stack
install.sh                  Interactive installer (Docker + NetBird + config)
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

## Quick Start

See [INSTALL.md](INSTALL.md) for the English setup guide.
See [DIEGIMAS.md](DIEGIMAS.md) for the Lithuanian setup guide.

## Operations

```bash
make status          # service health + listening ports
make logs            # follow all logs
make shell           # bash into config container
make add-user USERNAME=alice
make update          # pull latest, rebuild, restart
```
