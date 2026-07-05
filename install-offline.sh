#!/usr/bin/env bash
# TAK Server — offline installer + bundle builder, for closed/air-gapped
# networks that can't reach GitHub/Docker Hub/apt at all (e.g. governmental
# networks, offgrid comms).
#
# Two modes:
#   ./install-offline.sh bundle [output-dir]
#       Run on a CONNECTED machine: builds normally, packages the finished
#       images + Docker itself + deployment files into a folder. Copy that
#       whole folder to the offline machine (USB, local network push,
#       whatever your environment allows).
#   ./install-offline.sh
#       Run from INSIDE that folder, on the offline machine. No git clone,
#       no curl, no apt-get, no registry pulls — installs Docker from the
#       bundled binaries if missing, loads the images, brings it up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "$PWD")"

# ── Bundle mode: build the offline package on a connected machine ───────────
if [ "${1:-}" = "bundle" ]; then
    DOCKER_VERSION="29.6.1"
    COMPOSE_VERSION="v5.3.0"
    # shellcheck source=scripts/refresh_vendor.sh
    . "$SCRIPT_DIR/scripts/refresh_vendor.sh"

    BUNDLE_DIR="${2:-$SCRIPT_DIR/offline-bundle}"
    rm -rf "$BUNDLE_DIR"
    mkdir -p "$BUNDLE_DIR/images" "$BUNDLE_DIR/docker-bin"

    echo "Fetching Docker ${DOCKER_VERSION} static binaries + Compose ${COMPOSE_VERSION} plugin..."
    curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
        -o "$BUNDLE_DIR/docker-bin/docker.tgz"
    curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
        -o "$BUNDLE_DIR/docker-bin/docker-compose"
    chmod +x "$BUNDLE_DIR/docker-bin/docker-compose"
    cp "$SCRIPT_DIR/docker/containerd.service" "$SCRIPT_DIR/docker/docker.service" "$BUNDLE_DIR/docker-bin/"

    echo "Loading vendored images (fetching any not yet vendored)..."
    load_vendored_images "$SCRIPT_DIR/takserver-dist"

    echo "Building images (needs internet for this step only)..."
    cd "$SCRIPT_DIR"
    export GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    docker compose build

    echo "Saving images into $BUNDLE_DIR/images ..."
    docker save -o "$BUNDLE_DIR/images/takserver.tar"           takserver:local
    docker save -o "$BUNDLE_DIR/images/admin.tar"               admin:local
    docker save -o "$BUNDLE_DIR/images/nginx.tar"               nginx:alpine
    docker save -o "$BUNDLE_DIR/images/postgis.tar"             postgis/postgis:15-3.3
    docker save -o "$BUNDLE_DIR/images/docker-socket-proxy.tar" tecnativa/docker-socket-proxy:v0.4.2

    echo "Copying deployment files..."
    cp docker-compose.yml install-offline.sh Makefile "$BUNDLE_DIR/"
    cp -r scripts templates "$BUNDLE_DIR/"
    mkdir -p "$BUNDLE_DIR/admin"
    cp -r admin/nginx "$BUNDLE_DIR/admin/"
    mkdir -p "$BUNDLE_DIR/packages/tak-maps"

    echo ""
    echo "Bundle ready: $BUNDLE_DIR"
    echo "Copy this whole folder to the offline machine, then run: ./install-offline.sh"
    exit 0
fi

# ── Install mode: run from inside a bundle, on the offline machine ──────────
[ -f "$SCRIPT_DIR/docker-compose.yml" ] || { echo "Run this from inside a bundle produced by './install-offline.sh bundle', or run that first."; exit 1; }
[ -d "$SCRIPT_DIR/images" ] && ls "$SCRIPT_DIR"/images/*.tar >/dev/null 2>&1 \
    || { echo "No images/*.tar found — this doesn't look like a built bundle."; exit 1; }

ENV_FILE="$SCRIPT_DIR/takserver.env"
[ -t 0 ] || exec < /dev/tty 2>/dev/null || true
[[ $EUID -ne 0 ]] && { echo "  Re-running with sudo..."; exec sudo bash "$SCRIPT_DIR/install-offline.sh"; }

if ! command -v docker &>/dev/null; then
    echo "Docker not found — installing from bundled static binaries (no network used)..."
    [ -d "$SCRIPT_DIR/docker-bin" ] || {
        echo "docker-bin/ missing from this bundle — rebuild it with './install-offline.sh bundle'"
        exit 1
    }

    tar xzf "$SCRIPT_DIR/docker-bin/docker.tgz" -C /tmp
    cp /tmp/docker/* /usr/bin/
    rm -rf /tmp/docker

    mkdir -p /usr/local/lib/docker/cli-plugins
    cp "$SCRIPT_DIR/docker-bin/docker-compose" /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    cp "$SCRIPT_DIR/docker-bin/containerd.service" /etc/systemd/system/containerd.service
    cp "$SCRIPT_DIR/docker-bin/docker.service" /etc/systemd/system/docker.service
    groupadd -f docker
    systemctl daemon-reload
    systemctl enable --now containerd
    systemctl enable --now docker

    command -v docker &>/dev/null || { echo "Docker install failed — check systemctl status docker"; exit 1; }
fi

[ -n "${SUDO_USER:-}" ] && usermod -aG docker "$SUDO_USER"

for kv in "net.ipv4.tcp_keepalive_time=60" "net.ipv4.tcp_keepalive_intvl=10" "net.ipv4.tcp_keepalive_probes=6"; do
    key="${kv%%=*}"; val="${kv##*=}"
    grep -qE "^${key}=" /etc/sysctl.conf 2>/dev/null \
        && sed -i "s|^${key}=.*|${key}=${val}|" /etc/sysctl.conf \
        || echo "${key}=${val}" >> /etc/sysctl.conf
done
sysctl -p >/dev/null 2>&1

WT_BACKTITLE="TAK Server Offline Installer"
# shellcheck source=scripts/_tui.sh
. "$SCRIPT_DIR/scripts/_tui.sh"

gen_hex() { openssl rand -hex "${1:-16}"; }

# ── Welcome ───────────────────────────────────────────────────────────────────
wt_msg "Welcome" "TAK Server Offline Installer\n\nThis deploys the official Java TAK Server in Docker, along with an admin panel and package server, entirely from files already in this folder — no network access is used.\n\nUse Tab / arrow keys to move between fields, Enter to confirm." 14 72

# ── [1/6] Networking ──────────────────────────────────────────────────────────
# No VPN auto-install here (NetBird/Tailscale setup needs internet) — if one
# is already provisioned on this network, its interface is detected; otherwise
# enter the address manually.
TAK_SERVER_ADDRESS=""
_NB_IP=$(ip addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true
_TS_IP=$(ip addr show tailscale0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true

if [ -n "$_NB_IP" ] && [ -n "$_TS_IP" ]; then
    wt_menu _VPN_TAG "Networking [1/6]" "Both NetBird and Tailscale interfaces were found. Select which one remote devices should use:" \
        netbird "NetBird ($_NB_IP)" \
        tailscale "Tailscale ($_TS_IP)"
    [ "$_VPN_TAG" = "tailscale" ] && TAK_SERVER_ADDRESS="$_TS_IP" || TAK_SERVER_ADDRESS="$_NB_IP"
elif [ -n "$_NB_IP" ]; then
    TAK_SERVER_ADDRESS="$_NB_IP"
elif [ -n "$_TS_IP" ]; then
    TAK_SERVER_ADDRESS="$_TS_IP"
else
    wt_input_required TAK_SERVER_ADDRESS "Networking [1/6]" "Server IP or hostname (as reachable on this network):"
fi

wt_input TAK_SERVER_NAME "Networking [1/6]" "Server display name (shown in client packages/chat):" "TAK Server"

# ── [2/6] Certificate metadata ────────────────────────────────────────────────
wt_input COUNTRY             "Certificate Metadata [2/6]" "Country code (2 letters):"  "US"
wt_input STATE               "Certificate Metadata [2/6]" "State / Province:"          "Florida"
wt_input CITY                "Certificate Metadata [2/6]" "City:"                      "Tampa"
wt_input ORGANIZATION        "Certificate Metadata [2/6]" "Organization:"              "TAK Server"
wt_input ORGANIZATIONAL_UNIT "Certificate Metadata [2/6]" "Organizational unit:"       "Ops"

# ── [3/6] Admin panel ─────────────────────────────────────────────────────────
wt_input ADMIN_FIRST_USER "Admin Panel [3/6]" "Admin username:" "admin"
while true; do
    wt_password ADMIN_FIRST_PASS "Admin Panel [3/6]" "Admin password (minimum 12 characters):"
    [ ${#ADMIN_FIRST_PASS} -ge 12 ] && break
    wt_msg "Password too short" "Minimum 12 characters required." 8 50
done

# ── [4/6] Review ──────────────────────────────────────────────────────────────
_SUMMARY="Server address    : ${TAK_SERVER_ADDRESS}
Server name       : ${TAK_SERVER_NAME}
Country           : ${COUNTRY}
State             : ${STATE}
City              : ${CITY}
Organization      : ${ORGANIZATION}
Org unit          : ${ORGANIZATIONAL_UNIT}
Admin user        : ${ADMIN_FIRST_USER}
Admin password    : (set)
DB/cert passwords : (auto-generated)

Proceed with installation?"
wt_yesno "Review [4/6]" "$_SUMMARY" 18 72 || { clear; echo "Aborted."; exit 0; }

# ── [5/6] Write config ────────────────────────────────────────────────────────
POSTGRES_PASSWORD=$(gen_hex 16)
ADMIN_CERT_PASS=$(gen_hex 16)
TAKSERVER_CERT_PASS=$(gen_hex 16)
CA_PASS=$(gen_hex 16)
ADMIN_SECRET_KEY=$(gen_hex 32)

cat > "$ENV_FILE" << ENVEOF
# TAK Server configuration — generated $(date -u '+%Y-%m-%d %H:%M UTC')
# DO NOT commit this file to version control.

TAK_SERVER_ADDRESS=${TAK_SERVER_ADDRESS}
TAK_SERVER_NAME=${TAK_SERVER_NAME}

POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=cot
POSTGRES_USER=martiuser
POSTGRES_ADDRESS=takdb
POSTGRES_SUPERUSER=martiuser
POSTGRES_SUPER_PASSWORD=${POSTGRES_PASSWORD}

ADMIN_CERT_PASS=${ADMIN_CERT_PASS}
ADMIN_CERT_NAME=admin
TAKSERVER_CERT_PASS=${TAKSERVER_CERT_PASS}
CA_NAME=takserver-ca
CA_PASS=${CA_PASS}

COUNTRY=${COUNTRY}
STATE=${STATE}
CITY=${CITY}
ORGANIZATION=${ORGANIZATION}
ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}

LOGGING_JSON_ENABLED=true
LOGGING_CONFIG=/opt/tak/logback-stdout.xml

ADMIN_SECRET_KEY=${ADMIN_SECRET_KEY}
ADMIN_FIRST_USER=${ADMIN_FIRST_USER}
ADMIN_FIRST_PASS=${ADMIN_FIRST_PASS}
ENVEOF
chmod 600 "$ENV_FILE"

# ── [6/6] Load images & start (no build, no network) ──────────────────────────
cd "$SCRIPT_DIR"
docker compose --env-file "$ENV_FILE" down --remove-orphans 2>/dev/null || true

run_with_gauge "Images [6/6]" "Loading bundled images..." -- bash -c \
    'for f in "$0"/images/*.tar; do docker load -i "$f"; done' "$SCRIPT_DIR" \
    || fail "Loading bundled images failed (see output above)."

run_with_gauge "Start [6/6]" "Starting containers..." -- \
    docker compose --env-file "$ENV_FILE" up -d \
    || fail "Container startup failed (see output above)."

whiptail --backtitle "$WT_BACKTITLE" --title "Database" --infobox "Waiting for database..." 8 50
until docker compose --env-file "$ENV_FILE" exec -T takdb pg_isready -U martiuser -d cot >/dev/null 2>&1; do
    sleep 3
done

wt_msg "Installation Complete" "TAK Server is starting up.\n\nSSL CoT     : ${TAK_SERVER_ADDRESS}:8089\nHTTPS API   : https://${TAK_SERVER_ADDRESS}:8443\nPackages    : http://${TAK_SERVER_ADDRESS}:8888/\nAdmin panel : https://${TAK_SERVER_ADDRESS}:8889/\n\nAdmin user     : ${ADMIN_FIRST_USER}\nAdmin password : ${ADMIN_FIRST_PASS}" 18 72

clear
printf "\n"
printf "  TAK Server is starting up\n"
printf "\n"
printf "  %-18s  %s\n" "SSL CoT"       "${TAK_SERVER_ADDRESS}:8089"
printf "  %-18s  %s\n" "HTTPS API"     "https://${TAK_SERVER_ADDRESS}:8443"
printf "  %-18s  %s\n" "Packages"      "http://${TAK_SERVER_ADDRESS}:8888/"
printf "  %-18s  %s\n" "Admin panel"   "https://${TAK_SERVER_ADDRESS}:8889/"
printf "\n"
printf "  %-18s  %s\n" "Admin user"     "$ADMIN_FIRST_USER"
printf "  %-18s  %s\n" "Admin password" "$ADMIN_FIRST_PASS"
printf "\n"
printf "  Add users:  make add-user USERNAME=callsign\n"
printf "  Logs:       docker compose logs -f\n"
printf "\n"
