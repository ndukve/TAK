#!/usr/bin/env bash
# TAK Server — interactive installer (full-screen TUI)
set -euo pipefail

REPO_URL="https://github.com/ndukve/TAK.git"
INSTALL_DIR="${INSTALL_DIR:-$HOME/tak-server}"

# ── Bootstrap: clone repo if running via curl | bash ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "$PWD")"
if [ ! -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    echo "Bootstrapping — cloning repo to $INSTALL_DIR ..."
    command -v git &>/dev/null || { apt-get update -qq && apt-get install -y -qq git; }
    if [ -d "$INSTALL_DIR/.git" ]; then
        git -C "$INSTALL_DIR" pull --ff-only
    else
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
    git -C "$INSTALL_DIR" submodule update --init --recursive
    exec bash "$INSTALL_DIR/install.sh" < /dev/tty
fi

ENV_FILE="$SCRIPT_DIR/takserver.env"
[ -t 0 ] || exec < /dev/tty 2>/dev/null || true
[[ $EUID -ne 0 ]] && { echo "  Re-running with sudo..."; exec sudo bash "$SCRIPT_DIR/install.sh"; }

WT_BACKTITLE="TAK Server Installer"
# shellcheck source=scripts/_tui.sh
. "$SCRIPT_DIR/scripts/_tui.sh"
# shellcheck source=scripts/refresh_vendor.sh
. "$SCRIPT_DIR/scripts/refresh_vendor.sh"

gen_hex() { openssl rand -hex "${1:-16}"; }

# ── Existing install detected — offer reinstall instead of re-onboarding ────
if [ -f "$ENV_FILE" ]; then
    wt_menu _EXISTING_ACTION "Existing Installation" "takserver.env already exists. What do you want to do?" \
        reinstall "Reinstall (wipe images/containers, rebuild, keep data)" \
        reconfigure "Full reconfigure (re-answer all setup questions)" \
        cancel "Cancel"

    if [ "${_EXISTING_ACTION:-cancel}" = "reinstall" ]; then
        TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2-)
        POSTGRES_USER=$(grep '^POSTGRES_USER=' "$ENV_FILE" | cut -d= -f2-)
        POSTGRES_DB=$(grep '^POSTGRES_DB=' "$ENV_FILE" | cut -d= -f2-)

        if ! command -v docker &>/dev/null; then
            # Official vendor installer (get.docker.com) fetched fresh over HTTPS —
            # not checksum-pinned since it's a live, auto-updating script; the
            # trust boundary is the TLS connection to Docker's own domain.
            run_with_gauge "System Setup" "Installing Docker..." -- bash -c \
                "curl -fsSL https://get.docker.com | sh && systemctl enable --now docker" \
                || fail "Docker installation failed (see output above)."
        fi

        cd "$SCRIPT_DIR"
        run_with_gauge "Reinstall" "Stopping containers and removing images..." -- bash -c \
            "docker compose --env-file '$ENV_FILE' down --remove-orphans --rmi local" || true
        ok "Containers and images removed"

        run_with_gauge "Vendored Images" "Loading pre-fetched images (if any)..." -- \
            load_vendored_images "$SCRIPT_DIR/takserver-dist" \
            || fail "Loading vendored images failed (see output above)."

        GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
        export GIT_COMMIT
        run_with_gauge "Build" "Building TAK Server image (this can take a few minutes)..." -- \
            docker compose --env-file "$ENV_FILE" build \
            || fail "Image build failed (see output above)."

        run_with_gauge "Start" "Starting containers..." -- \
            docker compose --env-file "$ENV_FILE" up -d \
            || fail "Container startup failed (see output above)."

        whiptail --backtitle "$WT_BACKTITLE" --title "Database" --infobox "Waiting for database..." 8 50
        until docker compose --env-file "$ENV_FILE" exec -T takdb pg_isready \
            -U "${POSTGRES_USER:-martiuser}" -d "${POSTGRES_DB:-cot}" >/dev/null 2>&1; do
            sleep 3
        done

        wt_msg "Reinstall Complete" "TAK Server is starting up.\n\nSSL CoT     : ${TAK_SERVER_ADDRESS}:8089\nHTTPS API   : https://${TAK_SERVER_ADDRESS}:8443\nAdmin panel : https://${TAK_SERVER_ADDRESS}:8889/ (packages under /packages)" 14 72

        clear
        printf "\n"
        printf "  ${G}┌─────────────────────────────────────────────────┐${NC}\n"
        printf "  ${G}│${NC}          ${W}TAK Server is starting up${NC}               ${G}│${NC}\n"
        printf "  ${G}└─────────────────────────────────────────────────┘${NC}\n"
        printf "\n"
        printf "  ${DIM}%-18s${NC}  %s\n" "SSL CoT"     "${TAK_SERVER_ADDRESS}:8089"
        printf "  ${DIM}%-18s${NC}  %s\n" "HTTPS API"   "https://${TAK_SERVER_ADDRESS}:8443"
        printf "  ${DIM}%-18s${NC}  %s\n" "Admin panel" "https://${TAK_SERVER_ADDRESS}:8889/ (packages under /packages)"
        printf "\n"
        exit 0
    elif [ "${_EXISTING_ACTION:-cancel}" != "reconfigure" ]; then
        clear; echo "Aborted."; exit 0
    fi
    # "reconfigure" falls through to the normal onboarding below, overwriting takserver.env
fi

# ── Welcome ───────────────────────────────────────────────────────────────────
wt_msg "Welcome" "TAK Server Installer\n\nThis deploys the official Java TAK Server in Docker, along with an admin panel and package server.\n\nUse Tab / arrow keys to move between fields, Enter to confirm." 14 72

# ── [1/7] Networking ──────────────────────────────────────────────────────────
TAK_SERVER_ADDRESS=""
_NB_IP=$(ip addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true
_TS_IP=$(ip addr show tailscale0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true

if [ -n "$_NB_IP" ] && [ -n "$_TS_IP" ]; then
    wt_menu _VPN_TAG "Networking [1/7]" "Both NetBird and Tailscale are active. Select which one remote devices should use:" \
        netbird "NetBird ($_NB_IP)" \
        tailscale "Tailscale ($_TS_IP)"
    [ "$_VPN_TAG" = "tailscale" ] && TAK_SERVER_ADDRESS="$_TS_IP" || TAK_SERVER_ADDRESS="$_NB_IP"
elif [ -n "$_NB_IP" ]; then
    TAK_SERVER_ADDRESS="$_NB_IP"
elif [ -n "$_TS_IP" ]; then
    TAK_SERVER_ADDRESS="$_TS_IP"
else
    wt_menu _VPN_ACTION "Networking [1/7]" "No VPN detected. How should remote devices reach this server?" \
        netbird "Install NetBird (recommended)" \
        tailscale "Install Tailscale" \
        manual "Enter IP/hostname manually"

    case "$_VPN_ACTION" in
        netbird)
            wt_password VPN_KEY "NetBird" "NetBird setup key (app.netbird.io → Keys):"
            # Official vendor installer, same accepted trust model as the
            # Docker install above — see comment there.
            run_with_gauge "NetBird" "Installing NetBird..." -- bash -c \
                "curl -fsSL https://pkgs.netbird.io/install.sh | sh" \
                || fail "NetBird installation failed (see output above)."
            run_with_gauge "NetBird" "Connecting to NetBird..." -- \
                netbird up --setup-key="$VPN_KEY" \
                || fail "NetBird connection failed — check your setup key."
            sleep 3
            TAK_SERVER_ADDRESS=$(ip addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            [ -n "$TAK_SERVER_ADDRESS" ] || fail "Could not read wt0 IP after connecting."
            ;;
        tailscale)
            wt_password VPN_KEY "Tailscale" "Tailscale auth key (login.tailscale.com → Settings → Keys):"
            # Official vendor installer, same accepted trust model as the
            # Docker install above — see comment there.
            run_with_gauge "Tailscale" "Installing Tailscale..." -- bash -c \
                "curl -fsSL https://tailscale.com/install.sh | sh" \
                || fail "Tailscale installation failed (see output above)."
            run_with_gauge "Tailscale" "Connecting to Tailscale..." -- \
                tailscale up --authkey="$VPN_KEY" \
                || fail "Tailscale connection failed — check your auth key."
            sleep 3
            TAK_SERVER_ADDRESS=$(ip addr show tailscale0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            [ -n "$TAK_SERVER_ADDRESS" ] || fail "Could not read tailscale0 IP after connecting."
            ;;
        manual)
            wt_input_required TAK_SERVER_ADDRESS "Networking [1/7]" "Server IP or hostname:"
            ;;
    esac
fi

wt_input TAK_SERVER_NAME "Networking [1/7]" "Server display name (shown in client packages/chat):" "TAK Server"

# ── [2/7] Certificate metadata ────────────────────────────────────────────────
wt_input COUNTRY             "Certificate Metadata [2/7]" "Country code (2 letters):"  "US"
wt_input STATE               "Certificate Metadata [2/7]" "State / Province:"          "Florida"
wt_input CITY                "Certificate Metadata [2/7]" "City:"                      "Tampa"
wt_input ORGANIZATION        "Certificate Metadata [2/7]" "Organization:"              "TAK Server"
wt_input ORGANIZATIONAL_UNIT "Certificate Metadata [2/7]" "Organizational unit:"       "Ops"

# ── [3/7] Admin panel ─────────────────────────────────────────────────────────
wt_input ADMIN_FIRST_USER "Admin Panel [3/7]" "Admin username:" "admin"
while true; do
    wt_password ADMIN_FIRST_PASS "Admin Panel [3/7]" "Admin password (minimum 12 characters):"
    [ ${#ADMIN_FIRST_PASS} -ge 12 ] && break
    wt_msg "Password too short" "Minimum 12 characters required." 8 50
done

# ── [4/7] Review ──────────────────────────────────────────────────────────────
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
wt_yesno "Review [4/7]" "$_SUMMARY" 18 72 || { clear; echo "Aborted."; exit 0; }

# ── [5/7] System setup ────────────────────────────────────────────────────────
if ! getent hosts debian.org >/dev/null 2>&1; then
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    getent hosts debian.org >/dev/null 2>&1 || fail "DNS still broken — fix /etc/resolv.conf and retry"
fi

if ! command -v docker &>/dev/null; then
    # Official vendor installer (get.docker.com) fetched fresh over HTTPS —
    # not checksum-pinned since it's a live, auto-updating script; the
    # trust boundary is the TLS connection to Docker's own domain.
    run_with_gauge "System Setup [5/7]" "Installing Docker..." -- bash -c \
        "curl -fsSL https://get.docker.com | sh && systemctl enable --now docker" \
        || fail "Docker installation failed (see output above)."
fi

[ -n "${SUDO_USER:-}" ] && usermod -aG docker "$SUDO_USER"

for kv in "net.ipv4.tcp_keepalive_time=60" "net.ipv4.tcp_keepalive_intvl=10" "net.ipv4.tcp_keepalive_probes=6"; do
    key="${kv%%=*}"; val="${kv##*=}"
    grep -qE "^${key}=" /etc/sysctl.conf 2>/dev/null \
        && sed -i "s|^${key}=.*|${key}=${val}|" /etc/sysctl.conf \
        || echo "${key}=${val}" >> /etc/sysctl.conf
done
sysctl -p >/dev/null 2>&1

# ── [6/7] Write config ────────────────────────────────────────────────────────
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

# ── [7/7] Build & start ───────────────────────────────────────────────────────
cd "$SCRIPT_DIR"
docker compose --env-file "$ENV_FILE" down --remove-orphans 2>/dev/null || true

run_with_gauge "Vendored Images [7/7]" "Loading pre-fetched images (if any)..." -- \
    load_vendored_images "$SCRIPT_DIR/takserver-dist" \
    || fail "Loading vendored images failed (see output above)."

GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
export GIT_COMMIT
run_with_gauge "Build [7/7]" "Building TAK Server image (this can take a few minutes)..." -- \
    docker compose --env-file "$ENV_FILE" build \
    || fail "Image build failed (see output above)."

run_with_gauge "Start [7/7]" "Starting containers..." -- \
    docker compose --env-file "$ENV_FILE" up -d \
    || fail "Container startup failed (see output above)."

whiptail --backtitle "$WT_BACKTITLE" --title "Database" --infobox "Waiting for database..." 8 50
until docker compose --env-file "$ENV_FILE" exec -T takdb pg_isready -U martiuser -d cot >/dev/null 2>&1; do
    sleep 3
done

wt_msg "Installation Complete" "TAK Server is starting up.\n\nSSL CoT     : ${TAK_SERVER_ADDRESS}:8089\nHTTPS API   : https://${TAK_SERVER_ADDRESS}:8443\nAdmin panel : https://${TAK_SERVER_ADDRESS}:8889/ (packages under /packages)\n\nAdmin user     : ${ADMIN_FIRST_USER}\nAdmin password : ${ADMIN_FIRST_PASS}" 18 72

# ── Done (plain-text summary stays in scrollback) ────────────────────────────
clear
printf "\n"
printf "  ${G}┌─────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}          ${W}TAK Server is starting up${NC}               ${G}│${NC}\n"
printf "  ${G}└─────────────────────────────────────────────────┘${NC}\n"
printf "\n"
printf "  ${DIM}%-18s${NC}  %s\n" "SSL CoT"       "${TAK_SERVER_ADDRESS}:8089"
printf "  ${DIM}%-18s${NC}  %s\n" "HTTPS API"     "https://${TAK_SERVER_ADDRESS}:8443"
printf "  ${DIM}%-18s${NC}  %s\n" "Admin panel"   "https://${TAK_SERVER_ADDRESS}:8889/ (packages under /packages)"
printf "\n"
printf "  ${DIM}%-18s${NC}  ${W}%s${NC}\n" "Admin user"     "$ADMIN_FIRST_USER"
printf "  ${DIM}%-18s${NC}  ${W}%s${NC}\n" "Admin password" "$ADMIN_FIRST_PASS"
printf "\n"
printf "  ${DIM}Add users:${NC}  make add-user USERNAME=callsign\n"
printf "  ${DIM}Logs:${NC}       docker compose logs -f\n"
printf "\n"
