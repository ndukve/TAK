#!/usr/bin/env bash
# Runs once on first boot — loads Docker images and launches TAK server setup
set -euo pipefail
umask 077

TTY=/dev/tty1
exec > >(tee -a /var/log/tak-firstboot.log) 2>&1

clear_tty() { echo -e "\033[2J\033[H" > "$TTY" 2>/dev/null || true; }
print_tty() { echo "$1" > "$TTY" 2>/dev/null || true; echo "$1"; }

clear_tty
print_tty "=========================================="
print_tty "  TAK Server — First Boot Setup"
print_tty "=========================================="
print_tty ""

# ── Load bundled Docker images ──────────────────────────────────────────────
IMAGES_TAR="/opt/tak-server/build-iso/docker-images.tar.gz"
if [[ -f "$IMAGES_TAR" ]]; then
    print_tty "[1/4] Loading Docker images (this may take a few minutes)..."
    docker load < "$IMAGES_TAR"
    print_tty "      Images loaded."
else
    print_tty "[1/4] No bundled images found — will pull from internet."
fi

# ── Collect configuration ────────────────────────────────────────────────────
print_tty ""
print_tty "[2/4] Configuration"
print_tty ""

# Detect primary IP
DEFAULT_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
DEFAULT_IP="${DEFAULT_IP:-127.0.0.1}"

read -rp "    Server IP address [$DEFAULT_IP]: " SERVER_IP < /dev/tty
SERVER_IP="${SERVER_IP:-$DEFAULT_IP}"

read -rp "    Admin panel username [admin]: " ADMIN_USER < /dev/tty
ADMIN_USER="${ADMIN_USER:-admin}"

while true; do
    read -rsp "    Host console password (min 12 chars): " HOST_PASS < /dev/tty
    echo ""
    [[ ${#HOST_PASS} -ge 12 ]] || { print_tty "    Password too short — must be at least 12 characters."; continue; }
    read -rsp "    Confirm host console password: " HOST_PASS2 < /dev/tty
    echo ""
    [[ "$HOST_PASS" = "$HOST_PASS2" ]] && break
    print_tty "    Passwords do not match. Try again."
done

# The autoinstall account is deliberately locked in user-data. Unlock it only
# after a unique password has been entered locally, and force a change on the
# first console login. SSH password authentication remains disabled.
printf 'tak:%s\n' "$HOST_PASS" | chpasswd
chage -d 0 tak
unset HOST_PASS HOST_PASS2

while true; do
    read -rsp "    Admin panel password (min 12 chars): " ADMIN_PASS < /dev/tty
    echo ""
    if [[ ${#ADMIN_PASS} -ge 12 ]]; then break; fi
    print_tty "    Password too short — must be at least 12 characters."
done

read -rsp "    Confirm admin password: " ADMIN_PASS2 < /dev/tty
echo ""
if [[ "$ADMIN_PASS" != "$ADMIN_PASS2" ]]; then
    print_tty "Passwords do not match. Aborting."
    exit 1
fi

# Always generate the database credential. Printing it in a prompt would copy
# it into /var/log/tak-firstboot.log via the setup transcript.
POSTGRES_PASS=$(openssl rand -hex 16)
ADMIN_CERT_PASS=$(openssl rand -hex 16)
TAKSERVER_CERT_PASS=$(openssl rand -hex 16)
CA_PASS=$(openssl rand -hex 16)

# ── Write takserver.env ──────────────────────────────────────────────────────
print_tty ""
print_tty "[3/4] Writing configuration..."

cd /opt/tak-server

ADMIN_SECRET=$(openssl rand -hex 32)
DOCKER_SOCKET_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)
if [ -z "$DOCKER_SOCKET_GID" ]; then
    DOCKER_SOCKET_GID=$(getent group docker 2>/dev/null | cut -d: -f3 || true)
fi
DOCKER_SOCKET_GID=${DOCKER_SOCKET_GID:-0}

cat > takserver.env << EOF
# TAK Server configuration — generated on first boot $(date -u +%Y-%m-%dT%H:%M:%SZ)

TAK_SERVER_ADDRESS=${SERVER_IP}
TAK_SERVER_NAME=TAK Server

POSTGRES_DB=cot
POSTGRES_USER=martiuser
POSTGRES_PASSWORD=${POSTGRES_PASS}
POSTGRES_ADDRESS=takdb
POSTGRES_SUPERUSER=martiuser
POSTGRES_SUPER_PASSWORD=${POSTGRES_PASS}

ADMIN_CERT_PASS=${ADMIN_CERT_PASS}
ADMIN_CERT_NAME=admin
TAKSERVER_CERT_PASS=${TAKSERVER_CERT_PASS}
CA_NAME=takserver-ca
CA_PASS=${CA_PASS}

COUNTRY=US
STATE=NA
CITY=NA
ORGANIZATION=TAK Server
ORGANIZATIONAL_UNIT=Ops

LOGGING_JSON_ENABLED=true
LOGGING_CONFIG=/opt/tak/logback-stdout.xml

DOCKER_SOCKET_GID=${DOCKER_SOCKET_GID}

ADMIN_SECRET_KEY=${ADMIN_SECRET}
ADMIN_FIRST_USER=${ADMIN_USER}
ADMIN_FIRST_PASS=${ADMIN_PASS}
EOF
chmod 600 takserver.env

# ── Start TAK server ─────────────────────────────────────────────────────────
print_tty "[4/4] Starting TAK Server..."
docker compose up -d --no-build --pull never

# shellcheck source=../scripts/scrub_admin_secret.sh
. /opt/tak-server/scripts/scrub_admin_secret.sh
scrub_admin_bootstrap_secret /opt/tak-server/takserver.env

print_tty ""
print_tty "=========================================="
print_tty "  Setup complete!"
print_tty ""
print_tty "  TAK CoT (SSL):  ${SERVER_IP}:8089"
print_tty "  TAK HTTPS API:  https://${SERVER_IP}:8443"
print_tty "  Admin panel:    https://${SERVER_IP}:8889 (packages under /packages)"
print_tty ""
print_tty "  Admin login: ${ADMIN_USER}"
print_tty "=========================================="
print_tty ""
print_tty "Reboot recommended to fully apply all services."
