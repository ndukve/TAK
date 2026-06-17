# Design: Migrate to Official Java TAK Server (pvarki/docker-atak-server pattern)

**Date:** 2026-06-17
**Status:** Approved

## Goal

Replace FreeTAKServer (Python) with the official Java TAK Server, restructuring the repo to match `pvarki/docker-atak-server` almost exactly. Keep the interactive `install.sh` and add NetBird as an optional networking path alongside manual IP entry.

## Repository Structure

```
TAK/
├── docker/
│   └── entrypoint.sh            # minimal tini entrypoint (exec "$@")
├── scripts/
│   ├── firstrun.sh              # first-run: certs + DB schema init
│   ├── firstrun_rm.sh           # remove firstrun.done marker
│   ├── start-tak.sh             # start TAK services inside container
│   ├── makeCert.sh              # cert generation (overrides distribution default)
│   ├── make_client_zip.sh       # build client .zip using gomplate templates
│   ├── enable_user.sh           # enable user cert via UserManager.jar
│   ├── disable_admin.sh         # revoke admin via UserManager.jar
│   ├── enable_admin.sh          # grant admin via UserManager.jar
│   ├── delete_user.sh           # delete user cert
│   ├── takdb_base.sql           # PostgreSQL/PostGIS schema seed
│   └── serve_packages.py        # HTTP server for distributing client .zip files
├── templates/
│   ├── CoreConfig.tpl           # Gomplate template for TAK CoreConfig.xml
│   ├── TAKIgniteConfig.tpl      # Gomplate template for Ignite config
│   ├── logback-stdout.xml       # logback config for container log collection
│   └── missionpkg/              # mission package template (blueteam.pref + manifest)
│       ├── MANIFEST/
│       │   └── manifest.xml.tpl
│       └── content/
│           └── blueteam.pref.tpl
├── Dockerfile                   # multi-stage build (see below)
├── docker-compose.yml           # 7-service orchestration
├── takserver.env.example        # env template
├── install.sh                   # interactive installer
├── generate_user.sh             # thin wrapper → make_client_zip.sh in container
├── update.sh                    # git pull + rebuild
├── Makefile                     # operational targets
└── README.md                    # updated documentation
```

Files removed from current project: `supervisord.conf`, `packages/.gitkeep` (replaced by TAK server data volume).

## Dockerfile

Three-stage build matching the reference:

```
Stage 1: pvarki/tak-server-dist:$TAK_RELEASE
  → extract takserver-docker-*.zip to /tmp/takserver.zip

Stage 2: eclipse-temurin:17-noble (deps)
  → apt install: emacs-nox net-tools netcat-traditional vim nmon python3-lxml
                 unzip tini curl pwgen zip openssh-client postgresql-client jq
  → download wait-for-it.sh
  → COPY gomplate from hairyhenderson/gomplate:stable

Stage 3: install → run
  → COPY docker/entrypoint.sh
  → unzip TAK server to /opt/tak
  → COPY scripts /opt/scripts
  → COPY templates /opt/templates
  → ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
```

ARGs: `TEMURIN_VERSION=17`, `TAK_RELEASE=5.7-RELEASE-43`

## docker-compose.yml

Seven services on a single `taknet` bridge network. Two named volumes: `takdb_data`, `takserver_data`.

| Service | Image | Ports | Role |
|---|---|---|---|
| `takdb` | postgis/postgis:15-3.3 | — | PostgreSQL + PostGIS database |
| `takserver_initialization` | built image | — | Runs `firstrun.sh` once on startup |
| `takserver_config` | built image | 8089, 8443 | TAK config service |
| `takserver_messaging` | built image | — | Messaging, shares config network |
| `takserver_api` | built image | — | REST API, mounts update dir |
| `takserver_retention` | built image | — | Data retention |
| `takserver_pluginmanager` | built image | — | Plugin management |

Startup order: `takdb` (health check) → `takserver_initialization` → all other takserver services.

All takserver services load `takserver.env`.

## takserver.env.example

```
TAK_SERVER_ADDRESS=          # NetBird wg0 IP or manual address
TAK_SERVER_NAME=takserver

POSTGRES_PASSWORD=
POSTGRES_DB=cot
POSTGRES_USER=martiuser
POSTGRES_ADDRESS=takdb
POSTGRES_SUPERUSER=postgres
POSTGRES_SUPER_PASSWORD=

ADMIN_CERT_PASS=
ADMIN_CERT_NAME=admin
TAKSERVER_CERT_PASS=
CA_NAME=takserver-ca
CA_PASS=

COUNTRY=US
STATE=
CITY=
ORGANIZATION=
ORGANIZATIONAL_UNIT=

ENABLE_VERBOSE_LOGGING=json
CIPHER_SUITES=
LOGBACK_CONFIG=/opt/tak/logback-stdout.xml
```

## install.sh

Preserves the current interactive wizard style. Key changes:

**Networking section replaces Tailscale detection:**
```
── Networking ─────────────────────────────────
  Detecting NetBird...
  [if connected]: auto-detects wg0 IP → uses it silently
  [if not connected]:
    Options:
      1) Install & connect NetBird
      2) Enter server address manually
    → [1/2]: _

  [option 1]:
    → NetBird setup key: _
    → installs netbird, runs `netbird up --setup-key=<key>`
    → reads IP from `ip addr show wg0 | grep inet`
  [option 2]:
    → Server address (IP or hostname): _
```

**Secrets section (new vs current):**
Generates: `POSTGRES_PASSWORD`, `POSTGRES_SUPER_PASSWORD`, `ADMIN_CERT_PASS`, `TAKSERVER_CERT_PASS`, `CA_PASS` via `openssl rand -hex 16`.

**Certificate metadata section (new):**
Prompts for: COUNTRY, STATE, CITY, ORGANIZATION, ORGANIZATIONAL_UNIT (with defaults).

**Build & start:**
- `docker compose --env-file takserver.env build`
- `docker compose --env-file takserver.env up -d`
- Waits for `takdb` healthy via `docker compose exec takdb pg_isready`
- `firstrun.sh` runs automatically inside `takserver_initialization` container

**Removed from current install.sh:**
- Tailscale detection and setup
- Locale fix (not needed for Java server)
- TCP keepalive tuning (less relevant, but can keep)
- API token sync to SQLite (no longer applicable)

## generate_user.sh

Replaces the FTS cert-generation approach:

```bash
docker exec -e CLIENT_CERT_NAME="$1" takserver_config bash /opt/scripts/make_client_zip.sh
# then copy the zip from the container to DATA_DIR or serve it
```

Prints the download URL using the server address from `takserver.env`.

## Makefile

Targets:

```makefile
build, up, down, restart, update, logs, logs-db, status, shell
add-user USERNAME=alice   # calls generate_user.sh
list-packages             # ls certs/files/clientpkgs/
serve-packages            # runs scripts/serve_packages.py
```

## scripts/ Details

**firstrun.sh** — runs once per fresh data volume:
- Checks `/opt/tak/data/firstrun.done`; exits early if present
- Patches `cert-metadata.sh` country code from env
- Copies `makeCert.sh` override into place
- Seeds `/opt/tak/data/certs/` from `/opt/tak/certs/` if empty
- Symlinks `/opt/tak/certs` → `/opt/tak/data/certs/`
- Generates root CA, takserver cert, admin cert
- Waits for PostgreSQL via `wait-for-it.sh`
- Runs `SchemaManager.jar upgrade`
- Writes `firstrun.done`

**make_client_zip.sh** — generates client package:
- Generates random cert password via `pwgen`
- Creates temp dir with mission package template
- Runs `gomplate` to render `blueteam.pref.tpl` and `manifest.xml.tpl`
- Signs client cert with CA
- Bundles `.p12` + `truststore-root.p12` + rendered config into `.zip`
- Moves to `/opt/tak/data/certs/files/clientpkgs/`

**User management scripts** — all wrap `UserManager.jar` with `TAKCL_CORECONFIG_PATH`:
- `enable_user.sh USER_CERT_NAME=foo` → certmod
- `enable_admin.sh USER_CERT_NAME=foo` → adds admin role
- `disable_admin.sh USER_CERT_NAME=foo` → removes admin role
- `delete_user.sh USER_CERT_NAME=foo` → certmod delete

## Data Flow

```
install.sh
  → writes takserver.env
  → docker compose up
      takdb (PostGIS) ──healthy──► takserver_initialization
                                        → firstrun.sh
                                            → certs generated
                                            → DB schema applied
                                        ──done──► takserver_config (8089, 8443)
                                                  takserver_messaging
                                                  takserver_api
                                                  takserver_retention
                                                  takserver_pluginmanager

generate_user.sh / make add-user
  → docker exec takserver_config make_client_zip.sh
      → gomplate renders config
      → cert signed
      → .zip produced in container
  → serve_packages.py (port 8888) serves .zip to devices
```

## What Is Not Changing

- `update.sh` — same pattern (git pull + rebuild), just references `takserver.env` instead of `.env`
- `serve_packages.py` — kept as-is in `scripts/`
- Deployment target — still Proxmox LXC + Ubuntu 22.04

## Success Criteria

- `docker compose up` starts all 7 services cleanly on fresh volume
- `firstrun.sh` generates certs and initializes DB schema without manual intervention
- `generate_user.sh alice` produces a valid TAK client `.zip` downloadable via port 8888
- ATAK/iTAK can connect on port 8089 (SSL CoT) and 8443 (HTTPS API)
- install.sh NetBird path: installs netbird, detects wg0 IP, writes it to env, completes without error
- install.sh manual path: accepts any IP/hostname, completes without error
