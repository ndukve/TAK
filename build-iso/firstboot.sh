#!/usr/bin/env bash
# Runs once on first boot — loads Docker images and launches TAK server setup
set -euo pipefail

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

POSTGRES_PASS_DEFAULT=$(openssl rand -hex 16)
read -rp "    PostgreSQL password [$POSTGRES_PASS_DEFAULT]: " POSTGRES_PASS < /dev/tty
POSTGRES_PASS="${POSTGRES_PASS:-$POSTGRES_PASS_DEFAULT}"

# ── Write takserver.env ──────────────────────────────────────────────────────
print_tty ""
print_tty "[3/4] Writing configuration..."

cd /opt/tak-server

ADMIN_SECRET=$(openssl rand -hex 32)

cat > takserver.env << EOF
# TAK Server configuration — generated on first boot $(date -u +%Y-%m-%dT%H:%M:%SZ)

TAK_SERVER_ADDRESS=${SERVER_IP}

POSTGRES_DB=cot
POSTGRES_USER=martiuser
POSTGRES_PASSWORD=${POSTGRES_PASS}
POSTGRES_ADDRESS=takdb

ADMIN_SECRET_KEY=${ADMIN_SECRET}
ADMIN_FIRST_USER=${ADMIN_USER}
ADMIN_FIRST_PASS=${ADMIN_PASS}
EOF
chmod 600 takserver.env

# ── Start TAK server ─────────────────────────────────────────────────────────
print_tty "[4/4] Starting TAK Server..."
docker compose up -d

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
