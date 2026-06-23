# TAK Server

Production deployment of the official Java TAK Server 5.7, containerised with Docker Compose and integrated with NetBird for secure overlay networking. Supports ATAK, iTAK, and WinTAK clients.

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
| `pkg_server` | Lightweight HTTP server — distributes client packages on 8888 |

Client onboarding uses mutual TLS. Each user gets a signed certificate bundled into a TAK data package (`.zip`) containing server config, trust anchor, and ATAK preference defaults. Packages are served over HTTP and imported directly into the TAK client.

## Networking

All client traffic runs over a NetBird WireGuard overlay (`wt0`). No ports need to be exposed to the public internet — devices connect to the server via their shared NetBird IP.

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
generate_user.sh            Client package + cert generation
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

See [INSTALL.md](INSTALL.md) for English setup guide.
Lithuanian: [DIEGIMAS.md](DIEGIMAS.md).

## Operations

```bash
make status          # service health + listening ports
make logs            # follow all logs
make shell           # bash into config container
make add-user USERNAME=alice
make update          # pull latest, rebuild, restart
```
