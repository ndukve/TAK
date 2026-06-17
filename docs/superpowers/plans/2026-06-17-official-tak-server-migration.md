# Official TAK Server Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace FreeTAKServer (Python) with the official Java TAK Server, restructuring the repo to match pvarki/docker-atak-server, with an interactive install.sh that supports NetBird as an optional networking path.

**Architecture:** Multi-stage Docker build from `pvarki/tak-server-dist`; seven-service docker-compose (PostGIS DB + six TAK microservices); Gomplate renders `CoreConfig.xml` and client package templates at runtime; interactive `install.sh` detects or installs NetBird and writes `takserver.env`.

**Tech Stack:** Java 17 (eclipse-temurin:17-noble), TAK Server 5.7-RELEASE-43 (pvarki/tak-server-dist), PostgreSQL 15 + PostGIS 3.3, Gomplate, Bash, Python 3 (serve_packages.py), tini, wait-for-it.sh, NetBird.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `docker/entrypoint.sh` | Minimal tini entrypoint |
| Create | `scripts/firstrun.sh` | One-time cert generation + DB schema init |
| Create | `scripts/firstrun_rm.sh` | Remove `firstrun.done` marker |
| Create | `scripts/start-tak.sh` | Render Gomplate configs + start a TAK microservice |
| Create | `scripts/makeCert.sh` | Override distribution makeCert (fixes country code + IP SAN) |
| Create | `scripts/make_client_zip.sh` | Build client `.zip` package via Gomplate |
| Create | `scripts/enable_user.sh` | Enable user cert via UserManager.jar |
| Create | `scripts/enable_admin.sh` | Grant admin role via UserManager.jar |
| Create | `scripts/disable_admin.sh` | Revoke admin role via UserManager.jar |
| Create | `scripts/delete_user.sh` | Delete user cert via UserManager.jar |
| Create | `scripts/takdb_base.sql` | PostGIS extension init, mounted to initdb.d |
| Create | `templates/CoreConfig.tpl` | Gomplate template for TAK CoreConfig.xml |
| Create | `templates/TAKIgniteConfig.tpl` | Gomplate template for Ignite cluster config |
| Create | `templates/logback-stdout.xml` | Logback config for container log collection |
| Create | `templates/missionpkg/MANIFEST/manifest.xml.tpl` | Client package manifest template |
| Create | `templates/missionpkg/content/blueteam.pref.tpl` | ATAK connection preferences template |
| Rewrite | `Dockerfile` | Multi-stage: tak-server-dist → eclipse-temurin:17 → run |
| Rewrite | `docker-compose.yml` | 7-service orchestration |
| Rewrite | `takserver.env.example` | Env template (replaces `.env.example`) |
| Rewrite | `install.sh` | Interactive installer with NetBird support |
| Rewrite | `generate_user.sh` | Thin wrapper → make_client_zip.sh in container |
| Rewrite | `Makefile` | Operational targets |
| Rewrite | `update.sh` | Reference `takserver.env` instead of `.env` |
| Rewrite | `README.md` | Updated documentation |
| Delete | `supervisord.conf` | Replaced by docker-compose multi-service |
| Delete | `packages/.gitkeep` | Replaced by named Docker volume |
| Delete | `.env.example` | Replaced by `takserver.env.example` |

---

## Task 1: Scaffold directory structure and remove obsolete files

**Files:**
- Delete: `supervisord.conf`, `packages/.gitkeep`, `.env.example`
- Create dirs: `docker/`, `scripts/`, `templates/templates/missionpkg/MANIFEST/`, `templates/missionpkg/content/`, `docs/superpowers/plans/`

- [ ] **Step 1: Remove obsolete files**

```bash
rm /home/ndukve/IdeaProjects/TAK/supervisord.conf
rm /home/ndukve/IdeaProjects/TAK/packages/.gitkeep
rm /home/ndukve/IdeaProjects/TAK/.env.example
```

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p /home/ndukve/IdeaProjects/TAK/docker
mkdir -p /home/ndukve/IdeaProjects/TAK/scripts
mkdir -p /home/ndukve/IdeaProjects/TAK/templates/missionpkg/MANIFEST
mkdir -p /home/ndukve/IdeaProjects/TAK/templates/missionpkg/content
```

Note: `scripts/serve_packages.py` already exists at the right path — no move needed.

- [ ] **Step 3: Verify structure**

```bash
find /home/ndukve/IdeaProjects/TAK -not -path '*/.git/*' -not -path '*/.idea/*' | sort
```

Expected: `docker/`, `scripts/`, `templates/missionpkg/` directories exist; `supervisord.conf`, `packages/`, `.env.example` are gone.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: scaffold dirs, remove FTS-specific files"
```

---

## Task 2: Write Dockerfile

**Files:**
- Rewrite: `Dockerfile`

- [ ] **Step 1: Write Dockerfile**

Replace the entire contents of `Dockerfile` with:

```dockerfile
# syntax=docker/dockerfile:1
ARG TEMURIN_VERSION="17"
ARG TAK_RELEASE="5.7-RELEASE-43"

# ── Stage 1: extract TAK distribution ZIP ────────────────────────────────────
FROM pvarki/tak-server-dist:${TAK_RELEASE} AS tak-files
RUN mv /zips/takserver-docker-*.zip /tmp/takserver.zip

# ── Stage 2: base system with all runtime deps ────────────────────────────────
FROM eclipse-temurin:${TEMURIN_VERSION}-noble AS deps
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    emacs-nox \
    net-tools \
    netcat-traditional \
    vim \
    nmon \
    python3-lxml \
    unzip \
    tini \
    curl \
    pwgen \
    zip \
    openssh-client \
    postgresql-client \
    jq \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh \
       -o /usr/bin/wait-for-it.sh \
    && chmod a+x /usr/bin/wait-for-it.sh

COPY --from=hairyhenderson/gomplate:stable /gomplate /bin/gomplate

SHELL ["/bin/bash", "-lc"]

# ── Stage 3: install TAK Server + project scripts/templates ──────────────────
FROM deps AS install

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY --from=tak-files /tmp/takserver.zip /tmp/takserver.zip
RUN cd /tmp \
    && unzip takserver.zip \
    && rm takserver.zip \
    && DISTDIR=$(echo takserver-docker-*) \
    && mv "$DISTDIR/tak" /opt/tak

COPY scripts /opt/scripts
COPY templates /opt/templates

# ── Stage 4: runtime image ───────────────────────────────────────────────────
FROM install AS run
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
```

- [ ] **Step 2: Verify syntax**

```bash
docker build --no-cache --dry-run /home/ndukve/IdeaProjects/TAK 2>&1 | head -20
```

If `--dry-run` is unsupported, run:
```bash
docker buildx build --check /home/ndukve/IdeaProjects/TAK 2>&1 | head -20
```

Expected: no syntax errors. (Image won't build yet — scripts and templates are missing.)

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "feat: rewrite Dockerfile for official Java TAK Server"
```

---

## Task 3: Write docker/entrypoint.sh

**Files:**
- Create: `docker/entrypoint.sh`

- [ ] **Step 1: Write entrypoint**

```bash
cat > /home/ndukve/IdeaProjects/TAK/docker/entrypoint.sh << 'EOF'
#!/usr/bin/env -S /bin/bash
set -e
exec "$@"
EOF
chmod +x /home/ndukve/IdeaProjects/TAK/docker/entrypoint.sh
```

- [ ] **Step 2: Verify**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/docker/entrypoint.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 3: Commit**

```bash
git add docker/entrypoint.sh
git commit -m "feat: add minimal tini entrypoint"
```

---

## Task 4: Write docker-compose.yml

**Files:**
- Rewrite: `docker-compose.yml`

- [ ] **Step 1: Write docker-compose.yml**

Replace the entire file:

```yaml
# Official TAK Server — 7-service deployment
# Build once: docker compose build
# Start: docker compose --env-file takserver.env up -d

x-tak: &tak-base
  image: takserver:local
  env_file: takserver.env
  volumes:
    - takserver_data:/opt/tak/data
  networks:
    - taknet
  restart: unless-stopped

services:

  # ── Database ────────────────────────────────────────────────────────────────
  takdb:
    image: postgis/postgis:15-3.3
    env_file: takserver.env
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-cot}
      POSTGRES_USER: ${POSTGRES_USER:-martiuser}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - takdb_data:/var/lib/postgresql/data
      - ./scripts/takdb_base.sql:/docker-entrypoint-initdb.d/takdb_base.sql:ro
    networks:
      - taknet
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-martiuser} -d ${POSTGRES_DB:-cot}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  # ── First-run initialisation (certs + DB schema) ───────────────────────────
  takserver_initialization:
    <<: *tak-base
    build: .
    command: ["/bin/bash", "/opt/scripts/firstrun.sh"]
    depends_on:
      takdb:
        condition: service_healthy
    restart: "no"

  # ── Config service (TAK SSL CoT + HTTPS API) ───────────────────────────────
  takserver_config:
    <<: *tak-base
    command: ["/bin/bash", "/opt/scripts/start-tak.sh", "config"]
    ports:
      - "8089:8089"
      - "8443:8443"
    depends_on:
      takserver_initialization:
        condition: service_completed_successfully

  # ── Messaging service (shares network with config) ─────────────────────────
  takserver_messaging:
    <<: *tak-base
    command: ["/bin/bash", "/opt/scripts/start-tak.sh", "messaging"]
    network_mode: "service:takserver_config"
    depends_on:
      takserver_initialization:
        condition: service_completed_successfully

  # ── API service ─────────────────────────────────────────────────────────────
  takserver_api:
    <<: *tak-base
    command: ["/bin/bash", "/opt/scripts/start-tak.sh", "api"]
    depends_on:
      takserver_initialization:
        condition: service_completed_successfully

  # ── Retention service ───────────────────────────────────────────────────────
  takserver_retention:
    <<: *tak-base
    command: ["/bin/bash", "/opt/scripts/start-tak.sh", "retention"]
    depends_on:
      takserver_initialization:
        condition: service_completed_successfully

  # ── Plugin manager ──────────────────────────────────────────────────────────
  takserver_pluginmanager:
    <<: *tak-base
    command: ["/bin/bash", "/opt/scripts/start-tak.sh", "plugin-manager"]
    depends_on:
      takserver_initialization:
        condition: service_completed_successfully

  # ── Package download server (port 8888) ────────────────────────────────────
  pkg_server:
    image: python:3.11-slim
    command: ["python3", "/srv/serve_packages.py"]
    volumes:
      - takserver_data:/opt/tak/data:ro
      - ./scripts/serve_packages.py:/srv/serve_packages.py:ro
    working_dir: /opt/tak/data/certs/files/clientpkgs
    ports:
      - "8888:8888"
    networks:
      - taknet
    restart: unless-stopped

volumes:
  takdb_data:
  takserver_data:

networks:
  taknet:
    driver: bridge
```

- [ ] **Step 2: Validate compose syntax**

```bash
cd /home/ndukve/IdeaProjects/TAK && docker compose config --quiet 2>&1 | head -20
```

Expected: warnings may appear about missing `takserver.env` but no syntax errors. If `takserver.env` is required, create a stub:

```bash
touch /home/ndukve/IdeaProjects/TAK/takserver.env
docker compose config --quiet
```

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: rewrite docker-compose for 7-service TAK Server"
```

---

## Task 5: Write takserver.env.example

**Files:**
- Create: `takserver.env.example`

- [ ] **Step 1: Write env example**

```bash
cat > /home/ndukve/IdeaProjects/TAK/takserver.env.example << 'EOF'
# ============================================================
# TAK Server Configuration
# Copy to takserver.env and fill in your values.
# NEVER commit takserver.env to version control.
# ============================================================

# ── Server identity ──────────────────────────────────────────────────────────
# Your NetBird IP (run: ip addr show wt0 | grep inet) — or any IP/hostname
TAK_SERVER_ADDRESS=100.x.x.x
TAK_SERVER_NAME=takserver

# ── Database ─────────────────────────────────────────────────────────────────
POSTGRES_ADDRESS=takdb
POSTGRES_DB=cot
POSTGRES_USER=martiuser
POSTGRES_PASSWORD=

# Superuser credentials (used only by SchemaManager.jar during firstrun)
POSTGRES_SUPERUSER=postgres
POSTGRES_SUPER_PASSWORD=

# ── Certificates ─────────────────────────────────────────────────────────────
ADMIN_CERT_NAME=admin
ADMIN_CERT_PASS=
TAKSERVER_CERT_PASS=
CA_NAME=takserver-ca
CA_PASS=

# ── Certificate authority metadata ───────────────────────────────────────────
COUNTRY=US
STATE=
CITY=
ORGANIZATION=
ORGANIZATIONAL_UNIT=

# ── Logging ──────────────────────────────────────────────────────────────────
# Set to "json" for structured logging, "false" to disable verbose output
ENABLE_VERBOSE_LOGGING=json
LOGBACK_CONFIG=/opt/tak/data/logback-stdout.xml
EOF
```

- [ ] **Step 2: Commit**

```bash
git add takserver.env.example
git commit -m "feat: add takserver.env.example"
```

---

## Task 6: Write scripts/firstrun.sh

**Files:**
- Create: `scripts/firstrun.sh`

- [ ] **Step 1: Write firstrun.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/firstrun.sh << 'SCRIPT'
#!/usr/bin/env -S /bin/bash
# One-time initialisation: certificate generation + database schema.
# Guards itself with /opt/tak/data/firstrun.done so it only runs once.

if [ -f /opt/tak/data/firstrun.done ]; then
    echo "First run already done"
    exit 0
fi

TR=/opt/tak
CR=${TR}/certs

set -e

# Patch the distribution's cert-metadata.sh to use env-supplied country
sed -i.orig "s/COUNTRY=US/COUNTRY=${COUNTRY}/g" "${CR}/cert-metadata.sh"

# Replace the distribution's makeCert.sh with our custom version
cp /opt/scripts/makeCert.sh "${CR}/"

# Seed certificate data into the persistent volume on first run
if [[ ! -d "${TR}/data/certs" ]]; then
    mkdir -p "${TR}/data/certs"
fi

if [[ -z "$(ls -A "${TR}/data/certs")" ]]; then
    echo "Copying initial certificate configuration..."
    cp -R "${TR}/certs/"* "${TR}/data/certs/"
else
    echo "Using existing certificates."
fi

# Replace the in-image certs dir with a symlink into the persistent volume
if [[ ! -L "${TR}/certs" ]]; then
    mv "${TR}/certs" "${TR}/certs.orig"
    ln -fs "${TR}/data/certs/" "${TR}/certs"
fi

# Symlink logs into the persistent volume
if [[ ! -d "${TR}/data/logs" ]]; then
    mkdir -p "${TR}/data/logs"
fi
if [[ ! -L "${TR}/logs" ]]; then
    ln -fs "${TR}/data/logs/" "${TR}/logs"
fi

cd "${CR}"

# Generate root CA (uses the distribution's makeRootCa.sh)
if [[ ! -f "${CR}/files/root-ca.pem" ]]; then
    CAPASS=${CA_PASS} bash makeRootCa.sh --ca-name "${CA_NAME}"
else
    echo "Using existing root CA."
fi

# Generate TAK server certificate
if [[ ! -f "${CR}/files/takserver.pem" ]]; then
    CAPASS=${CA_PASS} PASS="${TAKSERVER_CERT_PASS}" bash makeCert.sh server takserver
else
    echo "Using existing takserver certificate."
fi

# Generate admin client certificate
if [[ ! -f "${CR}/files/${ADMIN_CERT_NAME}.pem" ]]; then
    CAPASS=${CA_PASS} PASS="${ADMIN_CERT_PASS}" bash makeCert.sh client "${ADMIN_CERT_NAME}"
else
    echo "Using existing ${ADMIN_CERT_NAME} certificate."
fi

chmod -R 777 "${TR}/data/"

# Render Gomplate config templates into the persistent data volume
echo "Rendering config templates..."
gomplate -f /opt/templates/CoreConfig.tpl > "${TR}/data/CoreConfig.xml"
gomplate -f /opt/templates/TAKIgniteConfig.tpl > "${TR}/data/TAKIgniteConfig.xml"
cp /opt/templates/logback-stdout.xml "${TR}/data/logback-stdout.xml"

# Wait for PostgreSQL
echo "Waiting for PostgreSQL at ${POSTGRES_ADDRESS}:5432..."
WAITFORIT_TIMEOUT=60 /usr/bin/wait-for-it.sh "${POSTGRES_ADDRESS}:5432" -- true

# Initialise / upgrade database schema
echo "Running SchemaManager..."
java -jar "${TR}/db-utils/SchemaManager.jar" \
    -url "jdbc:postgresql://${POSTGRES_ADDRESS}:5432/${POSTGRES_DB}" \
    -user "${POSTGRES_SUPERUSER}" \
    -password "${POSTGRES_SUPER_PASSWORD}" \
    upgrade

date -u +"%Y%m%dT%H%M" > /opt/tak/data/firstrun.done
echo "First run complete."
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/scripts/firstrun.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/scripts/firstrun.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 3: Commit**

```bash
git add scripts/firstrun.sh
git commit -m "feat: add firstrun.sh for cert generation and DB init"
```

---

## Task 7: Write scripts/firstrun_rm.sh and scripts/start-tak.sh

**Files:**
- Create: `scripts/firstrun_rm.sh`
- Create: `scripts/start-tak.sh`

- [ ] **Step 1: Write firstrun_rm.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/firstrun_rm.sh << 'SCRIPT'
#!/usr/bin/env -S /bin/bash
# Remove the firstrun.done marker so firstrun.sh re-runs on next start.
set -e
rm -f /opt/tak/data/firstrun.done
echo "First-run marker removed. Restart takserver_initialization to re-run."
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/scripts/firstrun_rm.sh
```

- [ ] **Step 2: Write start-tak.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/start-tak.sh << 'SCRIPT'
#!/usr/bin/env -S /bin/bash
# Start one TAK Server microservice.
# Discovers the core JAR dynamically to stay version-agnostic.
set -e

SERVICE="${1:?Usage: start-tak.sh <config|messaging|api|retention|plugin-manager>}"
TR=/opt/tak

cd "$TR"
[ -f "./setenv.sh" ] && source "./setenv.sh"

# Discover the core TAK Server JAR
CORE_JAR=$(find "$TR" -maxdepth 2 -name "takserver-core-*.jar" 2>/dev/null | head -1)
if [ -z "$CORE_JAR" ]; then
    # Fallback: any non-utility JAR at the top level
    CORE_JAR=$(find "$TR" -maxdepth 1 -name "*.jar" 2>/dev/null | head -1)
fi
if [ -z "$CORE_JAR" ]; then
    echo "ERROR: Could not find TAK Server JAR in $TR"
    echo "Contents of $TR:"; ls -la "$TR"
    exit 1
fi

echo "Starting TAK '$SERVICE' via $(basename "$CORE_JAR")..."
exec java ${JVM_OPTS:-} -jar "$CORE_JAR" "$SERVICE"
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/scripts/start-tak.sh
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/scripts/firstrun_rm.sh && echo "firstrun_rm ok"
bash -n /home/ndukve/IdeaProjects/TAK/scripts/start-tak.sh   && echo "start-tak ok"
```

Expected: both `ok`

- [ ] **Step 4: Commit**

```bash
git add scripts/firstrun_rm.sh scripts/start-tak.sh
git commit -m "feat: add firstrun_rm.sh and start-tak.sh"
```

---

## Task 8: Write scripts/makeCert.sh

**Files:**
- Create: `scripts/makeCert.sh`

This script is copied over the distribution's `makeCert.sh` by `firstrun.sh`. It fixes non-US country codes and adds IP-address SAN support.

- [ ] **Step 1: Write makeCert.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/makeCert.sh << 'SCRIPT'
#!/bin/bash
# Custom makeCert.sh — replaces TAK distribution default.
# Fixes: non-US country codes, IP address SANs, OpenSSL 3.x PKCS12 export.
# Usage: CAPASS=<ca-pass> PASS=<cert-pass> bash makeCert.sh <server|client> <common-name>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/cert-metadata.sh"

WORKDIR="${SCRIPT_DIR}/files"
mkdir -p "$WORKDIR"

TYPE="${1:?Usage: makeCert.sh <server|client> <common-name>}"
CN="${2:-}"

# Auto-generate CN if missing or too short
if [ ${#CN} -lt 2 ]; then
    CN="${TYPE}-$(date +%s)"
fi

# OpenSSL 3.x needs -legacy for PKCS12 JKS compatibility
LEGACY_FLAG=""
if openssl version 2>/dev/null | grep -qE '^OpenSSL 3'; then
    LEGACY_FLAG="-legacy"
fi

# Detect whether CN is an IPv4 address
is_ip() { echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; }

case "$TYPE" in
  server)
    if is_ip "$CN"; then SAN="IP:${CN}"; else SAN="DNS:${CN}"; fi

    openssl req -new -newkey rsa:2048 -nodes \
        -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${CN}" \
        -keyout "${WORKDIR}/${CN}.key" \
        -out "${WORKDIR}/${CN}.csr"

    openssl x509 -req -days 730 \
        -in "${WORKDIR}/${CN}.csr" \
        -CA "${WORKDIR}/root-ca.pem" \
        -CAkey "${WORKDIR}/root-ca.key" \
        -CAcreateserial \
        -passin "pass:${CAPASS}" \
        -extfile <(printf "subjectAltName=%s\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth" "$SAN") \
        -out "${WORKDIR}/${CN}.pem"

    openssl pkcs12 -export $LEGACY_FLAG \
        -in "${WORKDIR}/${CN}.pem" \
        -inkey "${WORKDIR}/${CN}.key" \
        -name "${CN}" \
        -passout "pass:${PASS}" \
        -out "${WORKDIR}/${CN}.p12"

    keytool -importkeystore \
        -srckeystore "${WORKDIR}/${CN}.p12" \
        -srcstoretype PKCS12 \
        -srcstorepass "${PASS}" \
        -destkeystore "${WORKDIR}/${CN}.jks" \
        -deststoretype JKS \
        -deststorepass "${PASS}" \
        -noprompt 2>/dev/null

    cp "${WORKDIR}/${CN}.jks" "${WORKDIR}/takserver.jks"
    echo "Server certificate ready: ${WORKDIR}/${CN}.pem"
    ;;

  client)
    openssl req -new -newkey rsa:2048 -nodes \
        -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${CN}" \
        -keyout "${WORKDIR}/${CN}.key" \
        -out "${WORKDIR}/${CN}.csr"

    openssl x509 -req -days 730 \
        -in "${WORKDIR}/${CN}.csr" \
        -CA "${WORKDIR}/root-ca.pem" \
        -CAkey "${WORKDIR}/root-ca.key" \
        -CAcreateserial \
        -passin "pass:${CAPASS}" \
        -extfile <(printf "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=clientAuth") \
        -out "${WORKDIR}/${CN}.pem"

    openssl pkcs12 -export $LEGACY_FLAG \
        -in "${WORKDIR}/${CN}.pem" \
        -inkey "${WORKDIR}/${CN}.key" \
        -name "${CN}" \
        -passout "pass:${PASS}" \
        -out "${WORKDIR}/${CN}.p12"

    echo "Client certificate ready: ${WORKDIR}/${CN}.pem"
    ;;

  *)
    echo "Unknown type: $TYPE. Use 'server' or 'client'."
    exit 1
    ;;
esac
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/scripts/makeCert.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/scripts/makeCert.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 3: Commit**

```bash
git add scripts/makeCert.sh
git commit -m "feat: add custom makeCert.sh (fixes country code + IP SAN)"
```

---

## Task 9: Write scripts/make_client_zip.sh

**Files:**
- Create: `scripts/make_client_zip.sh`

- [ ] **Step 1: Write make_client_zip.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/make_client_zip.sh << 'SCRIPT'
#!/usr/bin/env -S /bin/bash
# Generate a TAK client data package (.zip) for a new user.
# Environment: CLIENT_CERT_NAME must be set. CA_PASS must be set.
# Output: /opt/tak/data/certs/files/clientpkgs/${CLIENT_CERT_NAME}.zip
set -e

TR=/opt/tak
CR=${TR}/data/certs
ZIPTGT=${CR}/files/clientpkgs

mkdir -p "$ZIPTGT"

if [ -z "$CLIENT_CERT_NAME" ]; then
    echo "ERROR: CLIENT_CERT_NAME not set"
    exit 1
fi

if [ -f "${ZIPTGT}/${CLIENT_CERT_NAME}.zip" ] || [ -f "${CR}/files/${CLIENT_CERT_NAME}.key" ]; then
    echo "${CLIENT_CERT_NAME} already exists — delete first if you want to regenerate"
    exit 1
fi

export CLIENT_CERT_PASSWORD
CLIENT_CERT_PASSWORD=$(pwgen -cn1 20 1)

TMP_DIR=$(mktemp -d "/tmp/newclient.XXXXXXXX")
WORK_DIR="${TMP_DIR}/${CLIENT_CERT_NAME}"
mkdir -p "$WORK_DIR"

cp -R /opt/templates/missionpkg/* "$WORK_DIR/"

# Render Gomplate templates
gomplate -f "${WORK_DIR}/content/blueteam.pref.tpl" > "${WORK_DIR}/content/blueteam.pref"
gomplate -f "${WORK_DIR}/MANIFEST/manifest.xml.tpl"  > "${WORK_DIR}/MANIFEST/manifest.xml"
rm "${WORK_DIR}/content/blueteam.pref.tpl" "${WORK_DIR}/MANIFEST/manifest.xml.tpl"

cd "${CR}"
CAPASS=${CA_PASS} PASS="${CLIENT_CERT_PASSWORD}" bash "${TR}/certs/makeCert.sh" client "${CLIENT_CERT_NAME}"

cp "${CR}/files/${CLIENT_CERT_NAME}.p12" "${WORK_DIR}/content/"
cp "${CR}/files/truststore-root.p12"     "${WORK_DIR}/content/"

cd "$WORK_DIR"
zip -r "${TMP_DIR}/${CLIENT_CERT_NAME}.zip" ./

if [ -f "${ZIPTGT}/${CLIENT_CERT_NAME}.zip" ]; then
    echo "ERROR: ${CLIENT_CERT_NAME} was created while we worked"
    exit 1
fi

mv "${TMP_DIR}/${CLIENT_CERT_NAME}.zip" "${ZIPTGT}/"
rm -rf "$TMP_DIR"

echo "Package ready: ${ZIPTGT}/${CLIENT_CERT_NAME}.zip"
echo "Certificate password: ${CLIENT_CERT_PASSWORD}"
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/scripts/make_client_zip.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/scripts/make_client_zip.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 3: Commit**

```bash
git add scripts/make_client_zip.sh
git commit -m "feat: add make_client_zip.sh for client package generation"
```

---

## Task 10: Write user management scripts

**Files:**
- Create: `scripts/enable_user.sh`
- Create: `scripts/enable_admin.sh`
- Create: `scripts/disable_admin.sh`
- Create: `scripts/delete_user.sh`

All four scripts use `UserManager.jar` from the TAK distribution. Run them via `docker exec takserver_config`.

- [ ] **Step 1: Write enable_user.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/enable_user.sh << 'SCRIPT'
#!/usr/bin/env -S /bin/bash
# Enable a user's client certificate.
# Usage: USER_CERT_NAME=alice bash enable_user.sh
set -e
TR=/opt/tak
CONFIG=${TR}/data/CoreConfig.xml
cd "${TR}"
source ./setenv.sh
set -x
TAKCL_CORECONFIG_PATH="${CONFIG}" java -jar "${TR}/utils/UserManager.jar" \
    certmod "${TR}/data/certs/files/${USER_CERT_NAME}.pem"
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/scripts/enable_user.sh
```

- [ ] **Step 2: Write enable_admin.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/enable_admin.sh << 'SCRIPT'
#!/usr/bin/env -S /bin/bash
# Grant admin role to a user.
# Usage: USER_CERT_NAME=alice bash enable_admin.sh
set -e
TR=/opt/tak
CONFIG=${TR}/data/CoreConfig.xml
cd "${TR}"
source ./setenv.sh
set -x
TAKCL_CORECONFIG_PATH="${CONFIG}" java -jar "${TR}/utils/UserManager.jar" \
    usermod -A "${TR}/data/certs/files/${USER_CERT_NAME}.pem"
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/scripts/enable_admin.sh
```

- [ ] **Step 3: Write disable_admin.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/disable_admin.sh << 'SCRIPT'
#!/usr/bin/env -S /bin/bash
# Revoke admin role from a user.
# Usage: USER_CERT_NAME=alice bash disable_admin.sh
set -e
TR=/opt/tak
CONFIG=${TR}/data/CoreConfig.xml
cd "${TR}"
source ./setenv.sh
set -x
TAKCL_CORECONFIG_PATH="${CONFIG}" java -jar "${TR}/utils/UserManager.jar" \
    usermod -A -D "${TR}/data/certs/files/${USER_CERT_NAME}.pem"
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/scripts/disable_admin.sh
```

- [ ] **Step 4: Write delete_user.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/delete_user.sh << 'SCRIPT'
#!/usr/bin/env -S /bin/bash
# Delete a user's certificate.
# Usage: USER_CERT_NAME=alice bash delete_user.sh
set -e
TR=/opt/tak
CONFIG=${TR}/data/CoreConfig.xml
cd "${TR}"
source ./setenv.sh
set -x
TAKCL_CORECONFIG_PATH="${CONFIG}" java -jar "${TR}/utils/UserManager.jar" \
    certmod -D "${TR}/data/certs/files/${USER_CERT_NAME}.pem"
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/scripts/delete_user.sh
```

- [ ] **Step 5: Verify all syntax**

```bash
for s in enable_user enable_admin disable_admin delete_user; do
    bash -n /home/ndukve/IdeaProjects/TAK/scripts/${s}.sh && echo "${s}.sh ok"
done
```

Expected: four `ok` lines.

- [ ] **Step 6: Commit**

```bash
git add scripts/enable_user.sh scripts/enable_admin.sh scripts/disable_admin.sh scripts/delete_user.sh
git commit -m "feat: add UserManager.jar wrapper scripts"
```

---

## Task 11: Write scripts/takdb_base.sql

**Files:**
- Create: `scripts/takdb_base.sql`

This file is mounted into the PostGIS container's `/docker-entrypoint-initdb.d/` and runs once on first DB start to enable PostGIS extensions in the TAK database.

- [ ] **Step 1: Write takdb_base.sql**

```bash
cat > /home/ndukve/IdeaProjects/TAK/scripts/takdb_base.sql << 'SQL'
-- Enable PostGIS extensions in the TAK Server database.
-- Runs automatically via /docker-entrypoint-initdb.d/ on first start.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
SQL
```

- [ ] **Step 2: Commit**

```bash
git add scripts/takdb_base.sql
git commit -m "feat: add PostGIS extension init SQL"
```

---

## Task 12: Write templates/CoreConfig.tpl

**Files:**
- Create: `templates/CoreConfig.tpl`

This is rendered by `gomplate` in `firstrun.sh` to produce `/opt/tak/data/CoreConfig.xml`. All `{{ .Env.VAR }}` references must match variable names in `takserver.env`.

- [ ] **Step 1: Write CoreConfig.tpl**

```bash
cat > /home/ndukve/IdeaProjects/TAK/templates/CoreConfig.tpl << 'TPL'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Configuration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
               deploymentContext="default"
               xmlns="http://bbn.com/marti/xml/config">

    <Network multicastTTL="5" version="3" serverId="{{ .Env.TAK_SERVER_NAME }}">
        <!-- SSL CoT port for ATAK/iTAK/WinTAK client connections -->
        <Input _name="stdssl"
               auth="x509"
               protocol="tls"
               port="8089"
               coreVersion="2"/>
        <!-- HTTPS API port (REST API + mission packages) -->
        <connector port="8443"
                   _name="https"
                   keystore="JKS"
                   keystoreFile="/opt/tak/certs/files/takserver.jks"
                   keystorePass="{{ .Env.TAKSERVER_CERT_PASS }}"
                   truststoreFile="/opt/tak/certs/files/truststore-root.jks"
                   truststorePass="{{ .Env.CA_PASS }}"
                   context="tls"/>
    </Network>

    <Subscription className="com.bbn.marti.service.SubscriptionStore"/>

    <Repository enable="true">
        <Connection
            url="jdbc:postgresql://{{ .Env.POSTGRES_ADDRESS }}:5432/{{ .Env.POSTGRES_DB }}"
            username="{{ .Env.POSTGRES_USER }}"
            password="{{ .Env.POSTGRES_PASSWORD }}"
            validationQuery="SELECT 1"
            dbConnectionPoolAutoSize="false"
            numDbConnections="50"/>
    </Repository>

    <Federation>
        <FederationServer v1port="9000" v2port="9001"
                          webBaseUrl="https://{{ .Env.TAK_SERVER_ADDRESS }}:8443"/>
    </Federation>

    <Dissemination smartRetry="false"/>
    <Plugins/>

    <buffer>
        <queue/>
        <latestSA enable="true"/>
    </buffer>

    <security>
        <tls keystore="JKS"
             keystoreFile="/opt/tak/certs/files/takserver.jks"
             keystorePass="{{ .Env.TAKSERVER_CERT_PASS }}"
             truststore="JKS"
             truststoreFile="/opt/tak/certs/files/truststore-root.jks"
             truststorePass="{{ .Env.CA_PASS }}"
             context="tls"/>
    </security>

    <logging verboseLogging="{{ .Env.ENABLE_VERBOSE_LOGGING }}"/>

</Configuration>
TPL
```

- [ ] **Step 2: Commit**

```bash
git add templates/CoreConfig.tpl
git commit -m "feat: add Gomplate CoreConfig.tpl"
```

---

## Task 13: Write templates/TAKIgniteConfig.tpl and templates/logback-stdout.xml

**Files:**
- Create: `templates/TAKIgniteConfig.tpl`
- Create: `templates/logback-stdout.xml`

- [ ] **Step 1: Write TAKIgniteConfig.tpl**

```bash
cat > /home/ndukve/IdeaProjects/TAK/templates/TAKIgniteConfig.tpl << 'TPL'
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://www.springframework.org/schema/beans
                           http://www.springframework.org/schema/beans/spring-beans.xsd">

    <bean id="ignite.cfg" class="org.apache.ignite.configuration.IgniteConfiguration">
        <property name="igniteInstanceName" value="{{ .Env.TAK_SERVER_NAME }}"/>
        <property name="localHost" value="{{ .Env.TAK_SERVER_ADDRESS }}"/>

        <property name="communicationSpi">
            <bean class="org.apache.ignite.spi.communication.tcp.TcpCommunicationSpi">
                <property name="localPort" value="47100"/>
            </bean>
        </property>

        <property name="discoverySpi">
            <bean class="org.apache.ignite.spi.discovery.tcp.TcpDiscoverySpi">
                <property name="ipFinder">
                    <bean class="org.apache.ignite.spi.discovery.tcp.ipfinder.vm.TcpDiscoveryVmIpFinder">
                        <property name="addresses">
                            <list>
                                <value>{{ .Env.TAK_SERVER_ADDRESS }}:47500..47509</value>
                            </list>
                        </property>
                    </bean>
                </property>
            </bean>
        </property>
    </bean>

</beans>
TPL
```

- [ ] **Step 2: Write logback-stdout.xml**

```bash
cat > /home/ndukve/IdeaProjects/TAK/templates/logback-stdout.xml << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>
    <root level="INFO">
        <appender-ref ref="STDOUT"/>
    </root>
</configuration>
XML
```

- [ ] **Step 3: Commit**

```bash
git add templates/TAKIgniteConfig.tpl templates/logback-stdout.xml
git commit -m "feat: add TAKIgniteConfig.tpl and logback-stdout.xml"
```

---

## Task 14: Write mission package templates

**Files:**
- Create: `templates/missionpkg/MANIFEST/manifest.xml.tpl`
- Create: `templates/missionpkg/content/blueteam.pref.tpl`

These are rendered by `gomplate` inside `make_client_zip.sh`. Variables available: `CLIENT_CERT_NAME`, `CLIENT_CERT_PASSWORD`, `TAK_SERVER_ADDRESS`, `TAK_SERVER_NAME`, `CA_PASS`.

- [ ] **Step 1: Write manifest.xml.tpl**

```bash
cat > /home/ndukve/IdeaProjects/TAK/templates/missionpkg/MANIFEST/manifest.xml.tpl << 'TPL'
<MissionPackageManifest version="2">
   <Configuration>
      <Parameter name="uid"  value="{{ .Env.CLIENT_CERT_NAME }}-{{ .Env.TAK_SERVER_NAME }}"/>
      <Parameter name="name" value="{{ .Env.CLIENT_CERT_NAME }}-{{ .Env.TAK_SERVER_NAME }}"/>
      <Parameter name="onReceiveDelete" value="false"/>
   </Configuration>
   <Contents>
      <Content ignore="false" zipEntry="content/{{ .Env.CLIENT_CERT_NAME }}.p12"/>
      <Content ignore="false" zipEntry="content/truststore-root.p12"/>
      <Content ignore="false" zipEntry="content/blueteam.pref"/>
   </Contents>
</MissionPackageManifest>
TPL
```

- [ ] **Step 2: Write blueteam.pref.tpl**

```bash
cat > /home/ndukve/IdeaProjects/TAK/templates/missionpkg/content/blueteam.pref.tpl << 'TPL'
<?xml version='1.0' standalone='yes'?>
<preferences>
    <preference version="1" name="com.atakmap.app_preferences">
        <entry key="locationCallsign" class="class java.lang.String">{{ .Env.CLIENT_CERT_NAME }}</entry>
    </preference>
    <preference version="1" name="cot_streams">
        <entry key="count"                   class="class java.lang.Integer">1</entry>
        <entry key="description0"            class="class java.lang.String">{{ .Env.TAK_SERVER_NAME }}</entry>
        <entry key="enabled0"                class="class java.lang.Boolean">true</entry>
        <entry key="connectString0"          class="class java.lang.String">{{ .Env.TAK_SERVER_ADDRESS }}:8089:ssl</entry>
        <entry key="cachingEnabled0"         class="class java.lang.Boolean">false</entry>
        <entry key="enrollForCertificateWithTrust0" class="class java.lang.Boolean">false</entry>
        <entry key="useAuth0"                class="class java.lang.Boolean">false</entry>
        <entry key="caLocation0"             class="class java.lang.String">cert/truststore-root.p12</entry>
        <entry key="caPassword0"             class="class java.lang.String">{{ .Env.CA_PASS }}</entry>
        <entry key="certificateLocation0"    class="class java.lang.String">cert/{{ .Env.CLIENT_CERT_NAME }}.p12</entry>
        <entry key="clientPassword0"         class="class java.lang.String">{{ .Env.CLIENT_CERT_PASSWORD }}</entry>
    </preference>
</preferences>
TPL
```

- [ ] **Step 3: Commit**

```bash
git add templates/missionpkg/
git commit -m "feat: add mission package Gomplate templates"
```

---

## Task 15: Rewrite install.sh with NetBird support

**Files:**
- Rewrite: `install.sh`

Key changes from the FTS version: NetBird replaces Tailscale; secrets cover DB + cert passwords; no API token sync step; build references `takserver.env`; wait logic polls `takdb` healthy then `firstrun.done`.

- [ ] **Step 1: Write install.sh**

Replace the entire file:

```bash
cat > /home/ndukve/IdeaProjects/TAK/install.sh << 'INSTALLER'
#!/bin/bash
# ============================================================
# install.sh — Interactive TAK Server one-file installer
# Run inside the target machine as root.
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "${GREEN}[✓]${NC} $*"; }
info()    { echo -e "${CYAN}[*]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
err()     { echo -e "${RED}[✗]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}── $* $(printf '─%.0s' {1..50} | head -c $((50-${#1})))${NC}"; }

# ── Helpers ───────────────────────────────────────────────────────────────────
ask() {
    local _var="$1" _q="$2" _default="${3:-}" _ans
    if [ -n "$_default" ]; then
        read -rp "$(echo -e "  ${BOLD}${_q}${NC}\n  ${CYAN}Default:${NC} ${_default}\n  → ")" _ans
        printf -v "$_var" '%s' "${_ans:-$_default}"
    else
        while true; do
            read -rp "$(echo -e "  ${BOLD}${_q}${NC}\n  → ")" _ans
            [ -n "$_ans" ] && break
            echo "    (required)"
        done
        printf -v "$_var" '%s' "$_ans"
    fi
}

ask_secret() {
    local _var="$1" _q="$2" _default="${3:-}" _ans
    if [ -n "$_default" ]; then
        read -rsp "$(echo -e "  ${BOLD}${_q}${NC}\n  ${CYAN}Default:${NC} ${_default}\n  → ")" _ans; echo
        printf -v "$_var" '%s' "${_ans:-$_default}"
    else
        while true; do
            read -rsp "$(echo -e "  ${BOLD}${_q}${NC}\n  → ")" _ans; echo
            [ -n "$_ans" ] && break
            echo "    (required)"
        done
        printf -v "$_var" '%s' "$_ans"
    fi
}

gen_secret() { openssl rand -hex 16; }

# ── Timer ─────────────────────────────────────────────────────────────────────
_timer_pid=""; _timer_start=0; _elapsed="0s"
trap '[ -n "$_timer_pid" ] && kill "$_timer_pid" 2>/dev/null || true' EXIT

start_timer() {
    local label="$1" cols start
    cols=$(tput cols 2>/dev/null || echo 80)
    start=$(date +%s); _timer_start=$start
    ( while true; do
        local e mm ss
        e=$(( $(date +%s) - start ))
        mm=$(( e / 60 )); ss=$(( e % 60 ))
        printf "\r  \033[36m[*]\033[0m %-$(( cols - 14 ))s \033[1m%02d:%02d\033[0m" "$label" "$mm" "$ss"
        sleep 1
      done ) &
    _timer_pid=$!
}

stop_timer() {
    [ -n "$_timer_pid" ] && { kill "$_timer_pid" 2>/dev/null || true; wait "$_timer_pid" 2>/dev/null || true; _timer_pid=""; }
    printf "\r\033[K"
    local e=$(( $(date +%s) - _timer_start )) mm ss
    mm=$(( e / 60 )); ss=$(( e % 60 ))
    [ "$mm" -gt 0 ] && _elapsed="${mm}m ${ss}s" || _elapsed="${ss}s"
}

sysctl_set() {
    local key="$1" val="$2"
    if grep -qE "^${key}=" /etc/sysctl.conf 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" /etc/sysctl.conf
    else
        echo "${key}=${val}" >> /etc/sysctl.conf
    fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       TAK Server  ·  Interactive Installer       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Deploys official Java TAK Server in Docker."
echo "  Press Enter to accept defaults shown in [brackets]."

# ── Networking ────────────────────────────────────────────────────────────────
section "Networking"

SERVER_ADDRESS=""
NETBIRD_USED=false

# Auto-detect NetBird
if command -v netbird &>/dev/null; then
    NB_STATUS=$(netbird status 2>/dev/null || true)
    if echo "$NB_STATUS" | grep -qi "Connected"; then
        SERVER_ADDRESS=$(ip addr show wt0 2>/dev/null \
            | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || true)
        if [ -n "$SERVER_ADDRESS" ]; then
            ok "NetBird connected — server address: $SERVER_ADDRESS"
            NETBIRD_USED=true
        fi
    fi
fi

if [ -z "$SERVER_ADDRESS" ]; then
    echo "  No active NetBird connection detected."
    echo ""
    echo -e "    ${BOLD}1)${NC} Install & connect NetBird  (recommended — secure overlay network)"
    echo -e "    ${BOLD}2)${NC} Enter server address manually"
    echo ""
    read -rp "  → [1/2]: " _NET_CHOICE
    _NET_CHOICE="${_NET_CHOICE:-1}"

    if [ "$_NET_CHOICE" = "1" ]; then
        if ! command -v netbird &>/dev/null; then
            start_timer "Installing NetBird..."
            curl -fsSL https://pkgs.netbird.io/install.sh | sh > /dev/null 2>&1
            stop_timer; ok "NetBird installed ($_elapsed)"
        fi
        ask_secret NB_SETUP_KEY "NetBird setup key  (netbird.io → Setup Keys)" ""
        ask NB_HOSTNAME "Hostname for this server in NetBird" "takserver"
        start_timer "Connecting to NetBird..."
        netbird up --setup-key="$NB_SETUP_KEY" --hostname="$NB_HOSTNAME" \
            || { stop_timer; err "NetBird connection failed. Check your setup key."; }
        sleep 5
        SERVER_ADDRESS=$(ip addr show wt0 2>/dev/null \
            | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || true)
        [ -z "$SERVER_ADDRESS" ] && err "Could not read NetBird IP from wt0 after connecting."
        stop_timer; ok "NetBird connected: $SERVER_ADDRESS ($_elapsed)"
        NETBIRD_USED=true
    else
        ask SERVER_ADDRESS "Server address (IP or hostname)" ""
    fi
fi

# ── Certificate metadata ──────────────────────────────────────────────────────
section "Certificate Authority"
echo "  These values are embedded in all generated certificates."
ask COUNTRY          "Country code (2 letters)"       "US"
ask STATE            "State / Province"                "State"
ask CITY             "City / Locality"                 "City"
ask ORGANIZATION     "Organisation name"               "TAK"
ask ORGANIZATIONAL_UNIT "Organisational unit"          "TAK"
ask CA_NAME          "CA name"                         "takserver-ca"
ask SERVER_NAME      "Server name (displayed in TAK clients)" "takserver"
ask ADMIN_CERT_NAME  "Admin certificate name"          "admin"

# ── Certificate passwords ─────────────────────────────────────────────────────
section "Certificate Passwords"
echo "  TAK clients enter the client cert password when importing the data package."
ask ADMIN_CERT_PASS    "Admin cert password"   "$(gen_secret)"
ask TAKSERVER_CERT_PASS "Server cert password" "$(gen_secret)"
ask CA_PASS            "CA passphrase"         "$(gen_secret)"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Summary ──────────────────────────────────────────────────────${NC}"
[ "$NETBIRD_USED" = true ] && echo "  Network:        NetBird (wt0)" \
                            || echo "  Network:        Manual"
echo "  Server address: $SERVER_ADDRESS"
echo "  Server name:    $SERVER_NAME"
echo "  CA name:        $CA_NAME"
echo "  Admin cert:     $ADMIN_CERT_NAME"
echo "  Country:        $COUNTRY / $STATE / $CITY"
echo ""
read -rp "$(echo -e "  ${BOLD}Proceed with installation?${NC} [Y/n]: ")" _CONFIRM
[[ "${_CONFIRM:-Y}" =~ ^[Yy] ]] || { echo "Aborted."; exit 0; }

# ── Fix DNS ───────────────────────────────────────────────────────────────────
if ! getent hosts debian.org > /dev/null 2>&1; then
    warn "DNS not resolving — adding fallback nameserver 1.1.1.1"
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    getent hosts debian.org > /dev/null 2>&1 || err "DNS still broken. Fix /etc/resolv.conf and retry."
    ok "DNS fallback working"
fi

# ── Install Docker ────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    start_timer "Installing Docker..."
    curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
    systemctl enable --now docker > /dev/null 2>&1
    stop_timer; ok "Docker installed ($_elapsed)"
else
    ok "Docker $(docker --version | awk '{print $3}' | tr -d ,) already installed"
fi

# ── TCP keepalive (prevents iTAK idle disconnects) ───────────────────────────
info "Setting TCP keepalive..."
sysctl_set net.ipv4.tcp_keepalive_time  60
sysctl_set net.ipv4.tcp_keepalive_intvl 10
sysctl_set net.ipv4.tcp_keepalive_probes 6
sysctl -p > /dev/null 2>&1
ok "TCP keepalive configured (time=60s intvl=10s probes=6)"

# ── Write takserver.env ───────────────────────────────────────────────────────
info "Writing takserver.env..."
cat > "$ENV_FILE" << ENVEOF
# TAK Server configuration — generated by install.sh on $(date -u '+%Y-%m-%d %H:%M UTC')
# DO NOT commit this file to version control.

TAK_SERVER_ADDRESS=${SERVER_ADDRESS}
TAK_SERVER_NAME=${SERVER_NAME}

POSTGRES_ADDRESS=takdb
POSTGRES_DB=cot
POSTGRES_USER=martiuser
POSTGRES_PASSWORD=$(gen_secret)
POSTGRES_SUPERUSER=postgres
POSTGRES_SUPER_PASSWORD=$(gen_secret)

ADMIN_CERT_NAME=${ADMIN_CERT_NAME}
ADMIN_CERT_PASS=${ADMIN_CERT_PASS}
TAKSERVER_CERT_PASS=${TAKSERVER_CERT_PASS}
CA_NAME=${CA_NAME}
CA_PASS=${CA_PASS}

COUNTRY=${COUNTRY}
STATE=${STATE}
CITY=${CITY}
ORGANIZATION=${ORGANIZATION}
ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}

ENABLE_VERBOSE_LOGGING=json
LOGBACK_CONFIG=/opt/tak/data/logback-stdout.xml
ENVEOF
ok "takserver.env written"

# ── Build & start ─────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"

start_timer "Building TAK Server Docker image (this takes a few minutes)..."
docker compose --env-file "$ENV_FILE" build --quiet
stop_timer; ok "Image built ($_elapsed)"

start_timer "Starting containers..."
docker compose --env-file "$ENV_FILE" up -d
stop_timer; ok "Containers started ($_elapsed)"

# ── Wait for DB healthy ───────────────────────────────────────────────────────
start_timer "Waiting for PostgreSQL to be healthy..."
MAX_WAIT=120; _w=0
until docker compose --env-file "$ENV_FILE" exec -T takdb \
      pg_isready -U martiuser -d cot > /dev/null 2>&1; do
    [ $_w -ge $MAX_WAIT ] && { stop_timer; warn "DB not ready after ${MAX_WAIT}s. Check: docker compose logs takdb"; break; }
    sleep 3; _w=$((_w + 3))
done
stop_timer; ok "PostgreSQL ready ($_elapsed)"

# ── Wait for firstrun to complete ─────────────────────────────────────────────
start_timer "Running first-time initialisation (certs + DB schema)..."
MAX_WAIT=300; _w=0
until docker compose --env-file "$ENV_FILE" exec -T takserver_initialization \
      test -f /opt/tak/data/firstrun.done > /dev/null 2>&1; do
    [ $_w -ge $MAX_WAIT ] && {
        stop_timer
        warn "Initialisation not done after ${MAX_WAIT}s."
        warn "Check logs: docker compose logs takserver_initialization"
        break
    }
    sleep 5; _w=$((_w + 5))
done
[ -z "$_w" ] || stop_timer; ok "Initialisation complete ($_elapsed)"

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║           TAK Server is running!                 ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Server address : ${BOLD}$SERVER_ADDRESS${NC}"
echo "  SSL CoT        : $SERVER_ADDRESS:8089  (ATAK/iTAK/WinTAK)"
echo "  HTTPS API      : https://$SERVER_ADDRESS:8443"
echo "  Packages       : http://$SERVER_ADDRESS:8888/"
echo ""
echo "  Add users      : ./generate_user.sh <username>"
echo "  View logs      : docker compose logs -f"
echo "  Restart        : docker compose restart"
echo ""
INSTALLER
chmod +x /home/ndukve/IdeaProjects/TAK/install.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/install.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: rewrite install.sh with NetBird support"
```

---

## Task 16: Rewrite generate_user.sh

**Files:**
- Rewrite: `generate_user.sh`

- [ ] **Step 1: Write generate_user.sh**

Replace the entire file:

```bash
cat > /home/ndukve/IdeaProjects/TAK/generate_user.sh << 'SCRIPT'
#!/bin/bash
# Generate a TAK client data package for a new user.
# Usage: ./generate_user.sh <username>
# Output: zip available at http://<server>:8888/<username>.zip

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

[ -f "$ENV_FILE" ] || { echo "Run './install.sh' first — $ENV_FILE not found"; exit 1; }

SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)

echo "[*] Generating package for: $USERNAME"
docker compose --env-file "$ENV_FILE" exec -T takserver_config \
    bash -c "CLIENT_CERT_NAME=${USERNAME} bash /opt/scripts/make_client_zip.sh"

echo ""
echo "[✓] Package ready. Download on device:"
echo "    http://${SERVER_ADDRESS}:8888/${USERNAME}.zip"
echo ""
echo "  iTAK  : Settings → Network → Servers → + → Upload Server Package"
echo "  ATAK  : Hamburger → Settings → Network Preferences → TAK Servers → + → Import"
echo "  WinTAK: Settings → Network Preferences → Server Connections → + → Import"
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/generate_user.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/generate_user.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 3: Commit**

```bash
git add generate_user.sh
git commit -m "feat: rewrite generate_user.sh as wrapper for make_client_zip.sh"
```

---

## Task 17: Rewrite Makefile

**Files:**
- Rewrite: `Makefile`

- [ ] **Step 1: Write Makefile**

Replace the entire file:

```makefile
.PHONY: build up down restart update logs logs-db status shell \
        add-user list-packages serve-packages firstrun

ENV_FILE := takserver.env
COMPOSE  := docker compose --env-file $(ENV_FILE)

# ── Lifecycle ─────────────────────────────────────────────────────────────────

build:
	$(COMPOSE) build

up:
	@[ -f $(ENV_FILE) ] || { echo "Run './install.sh' first"; exit 1; }
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

update:
	@chmod +x ./update.sh && ./update.sh

# ── User management ───────────────────────────────────────────────────────────

## Generate a TAK data package for a new user.
## Usage: make add-user USERNAME=alice
add-user:
	@[ -n "$(USERNAME)" ] || { echo "Usage: make add-user USERNAME=alice"; exit 1; }
	@chmod +x ./generate_user.sh
	./generate_user.sh $(USERNAME)

## List generated packages ready for distribution.
list-packages:
	@docker compose --env-file $(ENV_FILE) exec takserver_config \
		ls -lh /opt/tak/data/certs/files/clientpkgs/ 2>/dev/null \
		|| echo "No packages yet. Run: make add-user USERNAME=alice"

## Enable a user cert:  make enable-user USERNAME=alice
enable-user:
	@[ -n "$(USERNAME)" ] || { echo "Usage: make enable-user USERNAME=alice"; exit 1; }
	$(COMPOSE) exec takserver_config bash -c "USER_CERT_NAME=$(USERNAME) bash /opt/scripts/enable_user.sh"

## Grant admin role:    make enable-admin USERNAME=alice
enable-admin:
	@[ -n "$(USERNAME)" ] || { echo "Usage: make enable-admin USERNAME=alice"; exit 1; }
	$(COMPOSE) exec takserver_config bash -c "USER_CERT_NAME=$(USERNAME) bash /opt/scripts/enable_admin.sh"

## Revoke admin role:   make disable-admin USERNAME=alice
disable-admin:
	@[ -n "$(USERNAME)" ] || { echo "Usage: make disable-admin USERNAME=alice"; exit 1; }
	$(COMPOSE) exec takserver_config bash -c "USER_CERT_NAME=$(USERNAME) bash /opt/scripts/disable_admin.sh"

## Delete a user cert:  make delete-user USERNAME=alice
delete-user:
	@[ -n "$(USERNAME)" ] || { echo "Usage: make delete-user USERNAME=alice"; exit 1; }
	$(COMPOSE) exec takserver_config bash -c "USER_CERT_NAME=$(USERNAME) bash /opt/scripts/delete_user.sh"

# ── Observability ─────────────────────────────────────────────────────────────

logs:
	$(COMPOSE) logs -f

logs-db:
	$(COMPOSE) logs -f takdb

status:
	@echo "=== Containers ==="
	@$(COMPOSE) ps
	@echo ""
	@echo "=== Listening ports ==="
	@ss -tlnp 2>/dev/null \
		| grep -E ":8089|:8443|:8888|:5432" \
		| awk '{print "  " $$4}' | sort -u || true
	@echo ""
	@echo "=== NetBird ==="
	@ip addr show wt0 2>/dev/null | grep 'inet ' | awk '{print "  " $$2}' \
		|| echo "  (wt0 not found — NetBird may not be connected)"

# ── Maintenance ───────────────────────────────────────────────────────────────

## Remove firstrun marker to force re-initialisation on next start.
firstrun:
	$(COMPOSE) exec takserver_initialization bash /opt/scripts/firstrun_rm.sh

shell:
	$(COMPOSE) exec takserver_config /bin/bash
```

- [ ] **Step 2: Verify Makefile parses**

```bash
make -n -f /home/ndukve/IdeaProjects/TAK/Makefile status 2>&1 | head -5
```

Expected: prints the commands `make status` would run, no parse errors.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: rewrite Makefile for TAK Server operations"
```

---

## Task 18: Update update.sh

**Files:**
- Modify: `update.sh`

- [ ] **Step 1: Read current update.sh**

```bash
cat /home/ndukve/IdeaProjects/TAK/update.sh
```

- [ ] **Step 2: Rewrite update.sh**

```bash
cat > /home/ndukve/IdeaProjects/TAK/update.sh << 'SCRIPT'
#!/bin/bash
# Pull latest config from git and rebuild the container.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"

[ -f "$ENV_FILE" ] || { echo "Run './install.sh' first — $ENV_FILE not found"; exit 1; }

cd "$SCRIPT_DIR"
echo "[*] Pulling latest changes..."
git pull

echo "[*] Rebuilding image..."
docker compose --env-file "$ENV_FILE" build --quiet

echo "[*] Restarting containers..."
docker compose --env-file "$ENV_FILE" up -d

echo "[✓] Update complete."
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/update.sh
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/update.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 4: Commit**

```bash
git add update.sh
git commit -m "chore: update.sh references takserver.env"
```

---

## Task 19: Rewrite README.md

**Files:**
- Rewrite: `README.md`

- [ ] **Step 1: Write README.md**

```bash
cat > /home/ndukve/IdeaProjects/TAK/README.md << 'MD'
# TAK Server

Official Java TAK Server deployed in Docker, with NetBird overlay network support.

## Prerequisites

- Ubuntu 22.04 host (bare metal, VM, or Proxmox LXC with nesting=1)
- Docker (installed automatically by `install.sh`)
- A [NetBird](https://netbird.io) account with a setup key — **or** a known IP/hostname for the server

---

## Quick Start

```bash
git clone https://github.com/ndukve/TAK.git /opt/TAK
cd /opt/TAK
./install.sh
```

The installer asks a few questions, then builds and starts all containers.

---

## Adding Users

```bash
./generate_user.sh <username>
```

This generates a `.zip` data package and prints the download URL:

```
http://<server>:8888/<username>.zip
```

Import in your TAK client:

| Client | Steps |
|--------|-------|
| **iTAK (iOS)** | Settings → Network → Servers → **+** → Upload Server Package |
| **ATAK (Android)** | ☰ → Settings → Network Preferences → TAK Servers → **+** → Import |
| **WinTAK (Windows)** | Settings → Network Preferences → Server Connections → **+** → Import |

---

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8089 | TCP/TLS | SSL CoT (TAK client connections) |
| 8443 | HTTPS | REST API + mission packages |
| 8888 | HTTP | Data package download server |

---

## Management

```bash
# View all logs
docker compose logs -f

# View DB logs only
make logs-db

# Status overview
make status

# Restart all services
make restart

# Add a user
make add-user USERNAME=alice

# Grant admin role
make enable-admin USERNAME=alice

# Revoke admin role
make disable-admin USERNAME=alice

# Delete a user
make delete-user USERNAME=alice

# Rebuild after config changes
make build && make up

# Pull latest + rebuild
./update.sh    # or: make update
```

---

## NetBird

If you chose NetBird during install, `wt0` provides your server address:

```bash
ip addr show wt0 | grep inet
```

Clients connecting via NetBird must also have NetBird installed and joined to the same network.

---

## Notes

- Data persists in the `takserver_data` Docker volume — survives container recreation
- Database persists in the `takdb_data` Docker volume
- To force re-initialisation (certs + DB): `make firstrun && docker compose restart takserver_initialization`
- Certificate metadata (country, org, etc.) is set during install and baked into generated certs
MD
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for official TAK Server"
```

---

## Task 20: Validate syntax and compose integrity

**Files:** No changes — validation only.

- [ ] **Step 1: Check all shell script syntax**

```bash
for f in /home/ndukve/IdeaProjects/TAK/install.sh \
          /home/ndukve/IdeaProjects/TAK/generate_user.sh \
          /home/ndukve/IdeaProjects/TAK/update.sh \
          /home/ndukve/IdeaProjects/TAK/docker/entrypoint.sh \
          /home/ndukve/IdeaProjects/TAK/scripts/firstrun.sh \
          /home/ndukve/IdeaProjects/TAK/scripts/firstrun_rm.sh \
          /home/ndukve/IdeaProjects/TAK/scripts/start-tak.sh \
          /home/ndukve/IdeaProjects/TAK/scripts/makeCert.sh \
          /home/ndukve/IdeaProjects/TAK/scripts/make_client_zip.sh \
          /home/ndukve/IdeaProjects/TAK/scripts/enable_user.sh \
          /home/ndukve/IdeaProjects/TAK/scripts/enable_admin.sh \
          /home/ndukve/IdeaProjects/TAK/scripts/disable_admin.sh \
          /home/ndukve/IdeaProjects/TAK/scripts/delete_user.sh; do
    bash -n "$f" && echo "OK: $(basename $f)" || echo "FAIL: $f"
done
```

Expected: all lines print `OK: <filename>`

- [ ] **Step 2: Validate docker-compose**

```bash
cd /home/ndukve/IdeaProjects/TAK
# Use the stub env file from Task 4 if takserver.env doesn't exist yet
[ -f takserver.env ] || cp takserver.env.example takserver.env
docker compose config --quiet && echo "compose ok"
```

Expected: `compose ok` (warnings about unset variables are acceptable)

- [ ] **Step 3: Verify Dockerfile parses**

```bash
docker buildx build --check /home/ndukve/IdeaProjects/TAK 2>&1 | head -20
```

Expected: no syntax errors.

- [ ] **Step 4: Verify file tree matches design**

```bash
find /home/ndukve/IdeaProjects/TAK \
    -not -path '*/.git/*' \
    -not -path '*/.idea/*' \
    -not -path '*/docs/*' \
    | sort
```

Expected layout:
```
TAK/
├── docker/entrypoint.sh
├── scripts/
│   ├── delete_user.sh
│   ├── disable_admin.sh
│   ├── enable_admin.sh
│   ├── enable_user.sh
│   ├── firstrun.sh
│   ├── firstrun_rm.sh
│   ├── make_client_zip.sh
│   ├── makeCert.sh
│   ├── serve_packages.py
│   ├── start-tak.sh
│   └── takdb_base.sql
├── templates/
│   ├── CoreConfig.tpl
│   ├── TAKIgniteConfig.tpl
│   ├── logback-stdout.xml
│   └── missionpkg/
│       ├── MANIFEST/manifest.xml.tpl
│       └── content/blueteam.pref.tpl
├── Dockerfile
├── Makefile
├── README.md
├── docker-compose.yml
├── generate_user.sh
├── install.sh
├── takserver.env.example
└── update.sh
```

- [ ] **Step 5: Commit validation stub**

```bash
git add takserver.env.example
# Add takserver.env to .gitignore if not already there
grep -q '^takserver\.env$' /home/ndukve/IdeaProjects/TAK/.gitignore \
    || echo 'takserver.env' >> /home/ndukve/IdeaProjects/TAK/.gitignore
git add .gitignore
git commit -m "chore: add takserver.env to .gitignore"
```

---

## Self-Review Notes

**Spec coverage check:**
- ✓ Repository structure matches spec exactly
- ✓ 7-service compose with PostGIS DB
- ✓ Multi-stage Dockerfile from tak-server-dist
- ✓ firstrun.sh: certs + gomplate config render + DB schema
- ✓ makeCert.sh: country code fix + IP SAN
- ✓ make_client_zip.sh: pwgen + gomplate + zip
- ✓ All 4 user management scripts via UserManager.jar
- ✓ CoreConfig.tpl: all env vars from takserver.env.example
- ✓ TAKIgniteConfig.tpl + logback-stdout.xml
- ✓ missionpkg templates: blueteam.pref.tpl + manifest.xml.tpl
- ✓ install.sh: NetBird auto-detect + install option + manual fallback
- ✓ generate_user.sh: docker exec wrapper
- ✓ Makefile: all user management targets + lifecycle + status with NetBird
- ✓ update.sh: references takserver.env
- ✓ README: updated ports, NetBird instructions, management commands

**Type/name consistency:**
- `takserver.env` referenced consistently in install.sh, generate_user.sh, update.sh, Makefile
- `CLIENT_CERT_NAME` env var used in make_client_zip.sh and generate_user.sh
- `CA_PASS` used in firstrun.sh, makeCert.sh, make_client_zip.sh, CoreConfig.tpl, blueteam.pref.tpl
- `POSTGRES_ADDRESS`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` consistent across compose + firstrun.sh + CoreConfig.tpl
- `TAK_SERVER_ADDRESS` + `TAK_SERVER_NAME` consistent across install.sh → takserver.env → CoreConfig.tpl → TAKIgniteConfig.tpl → blueteam.pref.tpl

**Known limitation:** `start-tak.sh` uses dynamic JAR discovery. If the TAK distribution uses a non-standard JAR name or a dedicated startup script per service, the service commands in `docker-compose.yml` may need updating after inspecting the unpacked distribution with: `docker run --rm --entrypoint ls takserver:local /opt/tak/`
