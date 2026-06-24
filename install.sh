#!/bin/bash
# ============================================================
# install.sh — Interactive TAK Server one-file installer
# Run inside the LXC container as root.
# ============================================================

set -euo pipefail

REPO_URL="https://github.com/ndukve/TAK.git"
INSTALL_DIR="${INSTALL_DIR:-$HOME/tak-server}"

# ── Bootstrap: clone repo if running via curl | bash ──────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "$PWD")"
if [ ! -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    echo "Bootstrapping — cloning repo to $INSTALL_DIR ..."
    if ! command -v git &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq git
    fi
    if [ -d "$INSTALL_DIR/.git" ]; then
        git -C "$INSTALL_DIR" pull --ff-only
    else
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
    git -C "$INSTALL_DIR" submodule update --init --recursive
    exec bash "$INSTALL_DIR/install.sh" < /dev/tty
fi

ENV_FILE="$SCRIPT_DIR/takserver.env"

# When run via curl | bash, stdin is the pipe — redirect to terminal so read works
[ -t 0 ] || exec < /dev/tty 2>/dev/null || true

# ── Require root ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "  Root privileges required — re-running with sudo..."
    exec sudo bash "$SCRIPT_DIR/install.sh"
fi

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
    local _var="$1" _q="$2" _default="${3:-}"
    local _ans
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
    local _var="$1" _q="$2"
    local _ans
    while true; do
        read -rsp "$(echo -e "  ${BOLD}${_q}${NC}\n  → ")" _ans; echo
        [ -n "$_ans" ] && break
        echo "    (required)"
    done
    printf -v "$_var" '%s' "$_ans"
}

gen_secret() { openssl rand -hex 16; }

# ── Timer helpers ─────────────────────────────────────────────────────────────
_timer_pid=""; _timer_start=0
trap '[ -n "$_timer_pid" ] && kill "$_timer_pid" 2>/dev/null' EXIT

start_timer() {
    local label="$1" cols start
    cols=$(tput cols 2>/dev/null || echo 80)
    start=$(date +%s)
    _timer_start=$start
    (
        while true; do
            local elapsed mm ss
            elapsed=$(( $(date +%s) - start ))
            mm=$(( elapsed / 60 )); ss=$(( elapsed % 60 ))
            printf "\r  \033[36m[*]\033[0m %-$(( cols - 14 ))s \033[1m%02d:%02d\033[0m" \
                "$label" "$mm" "$ss"
            sleep 1
        done
    ) &
    _timer_pid=$!
}

stop_timer() {
    [ -n "$_timer_pid" ] && {
        kill "$_timer_pid" 2>/dev/null || true
        wait "$_timer_pid" 2>/dev/null || true
        _timer_pid=""
    }
    printf "\r\033[K"
    local elapsed=$(( $(date +%s) - _timer_start ))
    local mm=$(( elapsed / 60 )) ss=$(( elapsed % 60 ))
    [ "$mm" -gt 0 ] && _elapsed="${mm}m ${ss}s" || _elapsed="${ss}s"
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  ▀▀█▀▀ █▀▀█ █░█   █▀▀ █▀▀ █▀▀█ █░░█ █▀▀ █▀▀█${NC}"
echo -e "${BOLD}  ░░█░░ █▄▄█ █▀▄   ▀▀█ █▀▀ █▄▄▀ ▀▄▄▀ █▀▀ █▄▄▀${NC}"
echo -e "${BOLD}  ░░▀░░ ▀░░▀ ▀░▀   ▀▀▀ ▀▀▀ ▀░▀▀ ░▀▀░ ▀▀▀ ▀░▀▀${NC}"
echo ""
echo -e "${BOLD}  Installer${NC}"
echo "  Deploys the official Java TAK Server in Docker."
echo "  Press Enter to accept defaults shown in [brackets]."

# ── Networking ────────────────────────────────────────────────────────────────
section "Networking"

TAK_SERVER_ADDRESS=""

_NB_IP=$(ip addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true
_TS_IP=$(ip addr show tailscale0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true

if [ -n "$_NB_IP" ] && [ -n "$_TS_IP" ]; then
    ok "NetBird detected: $_NB_IP"
    ok "Tailscale detected: $_TS_IP"
    echo ""
    echo "  1) Use NetBird ($_NB_IP)"
    echo "  2) Use Tailscale ($_TS_IP)"
    echo ""
    read -rp "  → [1/2]: " _VPN_CHOICE
    [ "${_VPN_CHOICE:-1}" = "2" ] && TAK_SERVER_ADDRESS="$_TS_IP" || TAK_SERVER_ADDRESS="$_NB_IP"
elif [ -n "$_NB_IP" ]; then
    TAK_SERVER_ADDRESS="$_NB_IP"
    ok "NetBird connected — wt0 IP: $TAK_SERVER_ADDRESS"
elif [ -n "$_TS_IP" ]; then
    TAK_SERVER_ADDRESS="$_TS_IP"
    ok "Tailscale connected — tailscale0 IP: $TAK_SERVER_ADDRESS"
else
    warn "No VPN detected."
    echo ""
    echo "  1) Install & connect NetBird"
    echo "  2) Install & connect Tailscale"
    echo "  3) Enter server address manually"
    echo ""
    read -rp "  → [1/2/3]: " _VPN_CHOICE
    case "${_VPN_CHOICE:-3}" in
        1)
            ask_secret VPN_KEY "NetBird setup key (app.netbird.io → Keys)"
            start_timer "Installing NetBird..."
            curl -fsSL https://pkgs.netbird.io/install.sh | sh > /dev/null 2>&1
            stop_timer; ok "NetBird installed ($_elapsed)"
            start_timer "Connecting to NetBird..."
            netbird up --setup-key="$VPN_KEY" > /dev/null 2>&1 \
                || { stop_timer; err "NetBird connection failed. Check your setup key."; }
            sleep 5
            TAK_SERVER_ADDRESS=$(ip addr show wt0 2>/dev/null \
                | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            [ -n "$TAK_SERVER_ADDRESS" ] || err "Could not read wt0 IP after connecting."
            stop_timer; ok "NetBird connected: $TAK_SERVER_ADDRESS ($_elapsed)"
            ;;
        2)
            ask_secret VPN_KEY "Tailscale auth key (login.tailscale.com → Settings → Keys)"
            start_timer "Installing Tailscale..."
            curl -fsSL https://tailscale.com/install.sh | sh > /dev/null 2>&1
            stop_timer; ok "Tailscale installed ($_elapsed)"
            start_timer "Connecting to Tailscale..."
            tailscale up --authkey="$VPN_KEY" > /dev/null 2>&1 \
                || { stop_timer; err "Tailscale connection failed. Check your auth key."; }
            sleep 5
            TAK_SERVER_ADDRESS=$(ip addr show tailscale0 2>/dev/null \
                | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            [ -n "$TAK_SERVER_ADDRESS" ] || err "Could not read tailscale0 IP after connecting."
            stop_timer; ok "Tailscale connected: $TAK_SERVER_ADDRESS ($_elapsed)"
            ;;
        *)
            ask TAK_SERVER_ADDRESS "Server address (IP or hostname)" ""
            ;;
    esac
fi

# ── Certificate metadata ──────────────────────────────────────────────────────
section "Certificate Metadata"
ask COUNTRY       "Country code (2 letters)" "US"
ask STATE         "State / Province"         ""
ask CITY          "City / Locality"          ""
ask ORGANIZATION  "Organization"             ""
ask ORGANIZATIONAL_UNIT "Organizational unit" ""

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Summary ──────────────────────────────────────────────────────${NC}"
echo "  Server address : $TAK_SERVER_ADDRESS"
echo "  Country        : $COUNTRY"
echo "  State          : $STATE"
echo "  City           : $CITY"
echo "  Organization   : $ORGANIZATION"
echo "  Org unit       : $ORGANIZATIONAL_UNIT"
echo "  Secrets        : (auto-generated)"
echo ""
read -rp "$(echo -e "  ${BOLD}Proceed with installation?${NC} [Y/n]: ")" _CONFIRM
[[ "${_CONFIRM:-Y}" =~ ^[Yy] ]] || { echo "Aborted."; exit 0; }

# ── Fix DNS ───────────────────────────────────────────────────────────────────
if ! getent hosts debian.org > /dev/null 2>&1; then
    warn "DNS not resolving — adding fallback nameserver 1.1.1.1"
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    getent hosts debian.org > /dev/null 2>&1 \
        || err "DNS still not working. Fix /etc/resolv.conf and retry."
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

if [ -n "${SUDO_USER:-}" ]; then
    usermod -aG docker "$SUDO_USER"
    ok "Added $SUDO_USER to docker group — no sudo needed for future docker commands"
fi

# ── TCP keepalive (prevents iTAK idle connection drops) ───────────────────────
for kv in "net.ipv4.tcp_keepalive_time=60" \
           "net.ipv4.tcp_keepalive_intvl=10" \
           "net.ipv4.tcp_keepalive_probes=6"; do
    key="${kv%%=*}"; val="${kv##*=}"
    if grep -qE "^${key}=" /etc/sysctl.conf 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" /etc/sysctl.conf
    else
        echo "${key}=${val}" >> /etc/sysctl.conf
    fi
done
sysctl -p > /dev/null 2>&1
ok "TCP keepalive configured (time=60s intvl=10s probes=6)"

# ── Generate secrets ──────────────────────────────────────────────────────────
info "Generating secrets..."
POSTGRES_PASSWORD=$(gen_secret)
POSTGRES_SUPER_PASSWORD=${POSTGRES_PASSWORD}
ADMIN_CERT_PASS=$(gen_secret)
TAKSERVER_CERT_PASS=$(gen_secret)
CA_PASS=$(gen_secret)
ok "Secrets generated"

# ── Write takserver.env ───────────────────────────────────────────────────────
info "Writing takserver.env..."
cat > "$ENV_FILE" << ENVEOF
# TAK Server configuration — generated by install.sh on $(date -u '+%Y-%m-%d %H:%M UTC')
# DO NOT commit this file to version control.

TAK_SERVER_ADDRESS=${TAK_SERVER_ADDRESS}
TAK_SERVER_NAME=takserver

POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=cot
POSTGRES_USER=martiuser
POSTGRES_ADDRESS=takdb
POSTGRES_SUPERUSER=martiuser
POSTGRES_SUPER_PASSWORD=${POSTGRES_SUPER_PASSWORD}

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
ENVEOF
ok "takserver.env written"

# ── Build & start ─────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"

info "Cleaning up any previous install attempt..."
docker compose --env-file "$ENV_FILE" down -v --remove-orphans 2>/dev/null || true

start_timer "Building TAK Server image..."
docker compose --env-file "$ENV_FILE" build --quiet
stop_timer; ok "Image built ($_elapsed)"

start_timer "Starting containers..."
docker compose --env-file "$ENV_FILE" up -d
stop_timer; ok "Containers started ($_elapsed)"

info "Waiting for database to be ready..."
until docker compose --env-file "$ENV_FILE" exec -T takdb \
    pg_isready -U martiuser -d cot > /dev/null 2>&1; do
    sleep 3
done
ok "Database ready"

info "firstrun.sh will run automatically inside takserver_initialization."
info "This generates certificates and initializes the DB schema (~2 min)."
info "Monitor progress with: docker compose --env-file takserver.env logs -f takserver_initialization"

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         TAK Server is starting up!               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Server address : ${BOLD}$TAK_SERVER_ADDRESS${NC}"
echo "  SSL CoT        : $TAK_SERVER_ADDRESS:8089"
echo "  HTTPS API      : https://$TAK_SERVER_ADDRESS:8443"
echo "  Packages       : http://$TAK_SERVER_ADDRESS:8888/"
echo ""
echo "  Add users      : ./generate_user.sh <username>"
echo "  View logs      : docker compose --env-file takserver.env logs -f"
echo "  Restart        : docker compose --env-file takserver.env restart"
echo ""
