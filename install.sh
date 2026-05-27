#!/bin/bash
# ============================================================
# install.sh — Interactive FreeTAKServer one-file installer
# Run inside the LXC container as root.
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${CYAN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}── $* $(printf '─%.0s' {1..50} | head -c $((50-${#1})))${NC}"; }

# ── Helpers ───────────────────────────────────────────────────────────────────
ask() {
    # ask VAR_NAME "Question" "default"
    local _var="$1" _q="$2" _default="${3:-}"
    local _ans
    if [ -n "$_default" ]; then
        read -rp "$(echo -e "  ${BOLD}${_q}${NC} [${_default}]: ")" _ans
        printf -v "$_var" '%s' "${_ans:-$_default}"
    else
        while true; do
            read -rp "$(echo -e "  ${BOLD}${_q}${NC}: ")" _ans
            [ -n "$_ans" ] && break
            echo "    (required)"
        done
        printf -v "$_var" '%s' "$_ans"
    fi
}

ask_secret() {
    local _var="$1" _q="$2" _default="${3:-}"
    local _ans
    if [ -n "$_default" ]; then
        read -rsp "$(echo -e "  ${BOLD}${_q}${NC} [${_default}]: ")" _ans; echo
        printf -v "$_var" '%s' "${_ans:-$_default}"
    else
        while true; do
            read -rsp "$(echo -e "  ${BOLD}${_q}${NC}: ")" _ans; echo
            [ -n "$_ans" ] && break
            echo "    (required)"
        done
        printf -v "$_var" '%s' "$_ans"
    fi
}

gen_secret() { python3 -c "import secrets; print(secrets.token_urlsafe(32))"; }

# ── Timer helpers ─────────────────────────────────────────────────────────────
_timer_pid=""; _timer_start=0; _elapsed="0s"
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
        kill "$_timer_pid" 2>/dev/null
        wait "$_timer_pid" 2>/dev/null
        _timer_pid=""
    }
    printf "\r\033[K"
    local elapsed=$(( $(date +%s) - _timer_start ))
    local mm=$(( elapsed / 60 )) ss=$(( elapsed % 60 ))
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
echo -e "${BOLD}║     FreeTAKServer  ·  Interactive Installer      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Deploys FreeTAKServer in Docker with Tailscale access."
echo "  Press Enter to accept defaults shown in [brackets]."

# ── Tailscale ─────────────────────────────────────────────────────────────────
section "Tailscale"

TS_CONNECTED=false
TS_IP=""
TS_HOSTNAME=""

if command -v tailscale &>/dev/null; then
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
fi

if [ -n "$TS_IP" ]; then
    ok "Already connected — Tailscale IP: $TS_IP"
    TS_HOSTNAME=$(tailscale status --json 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); \
          print(d.get('Self',{}).get('DNSName','').rstrip('.').split('.')[0])" \
        2>/dev/null || echo "freetakserver")
    TS_CONNECTED=true
    NEED_TS_AUTH=false
else
    warn "Tailscale not connected."
    if ! command -v tailscale &>/dev/null; then
        info "Tailscale will be installed."
    fi
    NEED_TS_AUTH=true
    ask_secret TS_AUTHKEY "Tailscale auth key  (login.tailscale.com/admin/settings/keys)" ""
    ask TS_HOSTNAME "Hostname for this server in Tailscale" "freetakserver"
fi

# ── Certificates ──────────────────────────────────────────────────────────────
section "Certificates"
echo "  TAK clients will be prompted for this password when importing .p12 files."
ask CERT_PASSWORD "Certificate password" "atakatak"
ask USER_CERT_VALIDITY_DAYS "User cert validity (days)" "365"

# ── Initial users ─────────────────────────────────────────────────────────────
section "Initial Users"
echo "  Packages will be generated for these users right after install."
echo "  Space-separated. Example: pilot1 pilot2 command"
echo "  Leave empty to skip (add users later with: ./generate_user.sh <name>)"
ask INITIAL_USERS "Usernames" ""

# ── Storage & ports ───────────────────────────────────────────────────────────
section "Storage & Ports"
ask DATA_DIR          "Host data directory (certs, DB, packages)" "/opt/fts"
ask COT_PORT          "CoT TCP port"  "8087"
ask SSL_COT_PORT      "CoT SSL port"  "8089"
ask API_PORT          "REST API port" "19023"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Summary ──────────────────────────────────────────────────────${NC}"
[ "$TS_CONNECTED" = true ] && echo "  Tailscale IP:      $TS_IP" \
                            || echo "  Tailscale key:     ${TS_AUTHKEY:0:24}..."
echo "  TS hostname:       $TS_HOSTNAME"
echo "  Cert password:     $CERT_PASSWORD"
echo "  Cert validity:     ${USER_CERT_VALIDITY_DAYS} days"
[ -n "$INITIAL_USERS" ] && echo "  Initial users:     $INITIAL_USERS" \
                         || echo "  Initial users:     (none — add later)"
echo "  Data dir:          $DATA_DIR"
echo "  Ports:             CoT=$COT_PORT  SSL=$SSL_COT_PORT  API=$API_PORT  UI=5000"
echo ""
read -rp "$(echo -e "  ${BOLD}Proceed with installation?${NC} [Y/n]: ")" _CONFIRM
[[ "${_CONFIRM:-Y}" =~ ^[Yy] ]] || { echo "Aborted."; exit 0; }

# ── Install Tailscale (if needed) ─────────────────────────────────────────────
if [ "$NEED_TS_AUTH" = true ]; then
    if ! command -v tailscale &>/dev/null; then
        start_timer "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh > /dev/null 2>&1
        systemctl enable --now tailscaled > /dev/null 2>&1 || true
        stop_timer; ok "Tailscale installed ($_elapsed)"
    fi
    start_timer "Connecting to Tailscale..."
    tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" --accept-routes \
        || { stop_timer; err "Tailscale connection failed. Check your auth key."; }
    TS_IP=$(tailscale ip -4) || err "Could not get Tailscale IP after connecting."
    stop_timer; ok "Tailscale connected: $TS_IP ($_elapsed)"
fi

# ── Fix locale (prevents Python/apt locale errors on minimal LXC images) ──────
start_timer "Configuring locale..."
apt-get install -y locales > /dev/null 2>&1
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen > /dev/null 2>&1
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
stop_timer; ok "Locale set to en_US.UTF-8 ($_elapsed)"

# ── Install Docker ────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    start_timer "Installing Docker..."
    curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
    systemctl enable --now docker > /dev/null 2>&1
    stop_timer; ok "Docker installed ($_elapsed)"
else
    ok "Docker $(docker --version | awk '{print $3}' | tr -d ,) already installed"
fi

# ── TCP keepalive (prevents iTAK idle connection drops) ───────────────────────
info "Setting TCP keepalive (prevents iTAK disconnects)..."
sysctl_set net.ipv4.tcp_keepalive_time 60
sysctl_set net.ipv4.tcp_keepalive_intvl 10
sysctl_set net.ipv4.tcp_keepalive_probes 6
sysctl -p > /dev/null 2>&1
ok "TCP keepalive configured (time=60s intvl=10s probes=6)"

# ── Create data directory ─────────────────────────────────────────────────────
info "Setting up data directory: $DATA_DIR"
mkdir -p "$DATA_DIR/certs/clientPackages"
chmod -R 777 "$DATA_DIR"
ok "Data directory ready"

# ── Write .env ────────────────────────────────────────────────────────────────
info "Writing .env..."
cat > "$ENV_FILE" << ENVEOF
# FreeTAKServer configuration
# Generated by install.sh on $(date -u '+%Y-%m-%d %H:%M UTC')
# DO NOT commit this file to version control.

FTS_IP="${TS_IP}"

CERT_PASSWORD="${CERT_PASSWORD}"
USER_CERT_VALIDITY_DAYS="${USER_CERT_VALIDITY_DAYS}"
INITIAL_USERS="${INITIAL_USERS}"

DATA_DIR="${DATA_DIR}"

COT_PORT=${COT_PORT}
SSL_COT_PORT=${SSL_COT_PORT}
API_PORT=${API_PORT}
WEB_PORT=${WEB_PORT}
SSL_WEB_PORT=8443
UI_PORT=5000

FTS_CONNECTION_MESSAGE="Connected to FreeTAKServer"
FTS_LOG_LEVEL="info"

FTS_WEBSOCKET_KEY=$(gen_secret)
FTS_SECRET_KEY=$(gen_secret)
FTS_FED_PASSWORD=$(gen_secret)
FTS_API_KEY=$(gen_secret)
ENVEOF
ok ".env written"

# ── Build & start ─────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"

start_timer "Building FTS Docker image..."
docker compose --env-file "$ENV_FILE" build --quiet
stop_timer; ok "Image built ($_elapsed)"

start_timer "Starting containers..."
docker compose --env-file "$ENV_FILE" up -d
stop_timer; ok "Containers started ($_elapsed)"

# ── Wait for FTS to generate its CA certificates ──────────────────────────────
start_timer "Waiting for FTS to generate CA certificate..."
MAX_WAIT=180; _cert_wait=0
until [ -f "$DATA_DIR/certs/ca.pem" ] && [ -f "$DATA_DIR/certs/server.p12" ]; do
    if [ $_cert_wait -ge $MAX_WAIT ]; then
        stop_timer
        warn "Timed out after ${MAX_WAIT}s — FTS may still be starting."
        warn "Check logs: docker logs freetakserver"
        warn "Then add users: ./generate_user.sh <username>"
        break
    fi
    sleep 3; _cert_wait=$((_cert_wait + 3))
done
if [ -f "$DATA_DIR/certs/ca.pem" ]; then stop_timer; ok "Certificates ready ($_elapsed)"; fi

# Ensure permissions after cert generation
chmod -R 777 "$DATA_DIR" 2>/dev/null || true

# ── Generate initial user packages ────────────────────────────────────────────
if [ -n "$INITIAL_USERS" ] && [ -f "$DATA_DIR/certs/ca.pem" ]; then
    info "Generating TAK packages for: $INITIAL_USERS"
    chmod +x "$SCRIPT_DIR/generate_user.sh"
    for user in $INITIAL_USERS; do
        "$SCRIPT_DIR/generate_user.sh" "$user" || warn "Failed to generate package for $user"
    done
    ok "Packages ready: $DATA_DIR/certs/clientPackages/"
fi

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         FreeTAKServer is running!                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Tailscale IP : ${BOLD}$TS_IP${NC}"
echo "  CoT  (TCP)   : $TS_IP:$COT_PORT"
echo "  CoT  (SSL)   : $TS_IP:$SSL_COT_PORT"
echo "  REST API     : http://$TS_IP:$API_PORT"
echo "  Web UI       : http://$TS_IP:5000"
echo ""
if [ -n "$INITIAL_USERS" ] && [ -f "$DATA_DIR/certs/ca.pem" ]; then
    echo "  Distribute packages to devices:"
    echo -e "    ${BOLD}make serve-packages${NC}  (starts HTTP server on port 8888)"
    echo "    Then on device: http://$TS_IP:8888/<username>.zip"
    echo ""
fi
echo "  Add users    : ./generate_user.sh <username>"
echo "  View logs    : docker logs freetakserver -f"
echo "  Restart      : docker compose restart"
echo ""
