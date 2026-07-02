#!/usr/bin/env bash
# TAK Server — interactive installer
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
[[ $EUID -ne 0 ]] && { echo "  Re-running with sudo..."; exec sudo TAK_REINSTALL="${TAK_REINSTALL:-}" bash "$SCRIPT_DIR/install.sh"; }

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m'
B='\033[0;34m' W='\033[1;37m' DIM='\033[2m' NC='\033[0m'

ok()      { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail()    { printf "${R}  ✗${NC}  %s\n" "$*"; exit 1; }
warn()    { printf "${Y}  !${NC}  %s\n" "$*"; }
info()    { printf "${C}  →${NC}  %s\n" "$*"; }
dim()     { printf "${DIM}     %s${NC}\n" "$*"; }

_STEP=0; _TOTAL=7
step() {
    _STEP=$(( _STEP + 1 ))
    printf "\n${W}  [%d/%d]${NC}  ${W}%s${NC}\n" "$_STEP" "$_TOTAL" "$*"
    printf "  %s\n" "$(printf '─%.0s' {1..56})"
}

# ── Spinner ───────────────────────────────────────────────────────────────────
_SP_PID=""; _SP_START=0
_SP_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

spin_start() {
    local msg="$1"
    _SP_START=$(date +%s)
    (
        local i=0
        while true; do
            local elapsed=$(( $(date +%s) - _SP_START ))
            printf "\r  ${C}%s${NC}  %s  ${DIM}%ds${NC}" \
                "${_SP_FRAMES[$((i % ${#_SP_FRAMES[@]}))]}" "$msg" "$elapsed"
            sleep 0.1
            i=$(( i + 1 ))
        done
    ) &
    _SP_PID=$!
}

spin_stop() {
    local label="$1"
    if [ -n "$_SP_PID" ]; then
        kill "$_SP_PID" 2>/dev/null || true
        wait "$_SP_PID" 2>/dev/null || true
        _SP_PID=""
    fi
    local elapsed=$(( $(date +%s) - _SP_START ))
    printf "\r\033[K"
    ok "$label ${DIM}(${elapsed}s)${NC}"
}

trap '[ -n "$_SP_PID" ] && kill "$_SP_PID" 2>/dev/null; printf "\r\033[K"' EXIT

# ── Prompt helpers ────────────────────────────────────────────────────────────
ask() {
    local _var="$1" _q="$2" _default="${3:-}" _ans
    if [ -n "$_default" ]; then
        printf "     ${W}%s${NC} ${DIM}[%s]${NC}: " "$_q" "$_default"
        read -r _ans
        printf -v "$_var" '%s' "${_ans:-$_default}"
    else
        while true; do
            printf "     ${W}%s${NC}: " "$_q"
            read -r _ans
            [ -n "$_ans" ] && break
            printf "     ${R}required${NC}\n"
        done
        printf -v "$_var" '%s' "$_ans"
    fi
}

ask_secret() {
    local _var="$1" _q="$2" _ans
    while true; do
        printf "     ${W}%s${NC}: " "$_q"
        read -rsp "" _ans; echo
        [ -n "$_ans" ] && break
        printf "     ${R}required${NC}\n"
    done
    printf -v "$_var" '%s' "$_ans"
}

pick() {
    # pick VARNAME "prompt" option1 option2 ...
    local _var="$1" _q="$2"; shift 2
    local _opts=("$@") _i _ans
    printf "     ${W}%s${NC}\n" "$_q"
    for _i in "${!_opts[@]}"; do
        printf "       ${C}%d)${NC} %s\n" "$(( _i + 1 ))" "${_opts[$_i]}"
    done
    while true; do
        printf "     ${W}→${NC} [1-%d]: " "${#_opts[@]}"
        read -r _ans
        [[ "$_ans" =~ ^[0-9]+$ ]] && (( _ans >= 1 && _ans <= ${#_opts[@]} )) && break
        printf "     ${R}Enter a number between 1 and %d${NC}\n" "${#_opts[@]}"
    done
    printf -v "$_var" '%s' "${_opts[$(( _ans - 1 ))]}"
}

gen_hex() { openssl rand -hex "${1:-16}"; }

# ── Banner ────────────────────────────────────────────────────────────────────
clear
printf "\n"
printf "${W}  ████████╗ █████╗ ██╗  ██╗${NC}\n"
printf "${W}     ██╔══╝██╔══██╗██║ ██╔╝${NC}\n"
printf "${W}     ██║   ███████║█████╔╝ ${NC}\n"
printf "${W}     ██║   ██╔══██║██╔═██╗ ${NC}\n"
printf "${W}     ██║   ██║  ██║██║  ██╗${NC}\n"
printf "${W}     ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝${NC}  ${DIM}Server Installer${NC}\n"
printf "\n"
printf "  Deploys the official Java TAK Server in Docker.\n"
printf "  ${DIM}Press Enter to accept defaults shown in [brackets].${NC}\n"
printf "\n"

# ── Reinstall fast path: reuse existing config, skip onboarding ─────────────────
if [ "${TAK_REINSTALL:-}" = "1" ] && [ -f "$ENV_FILE" ]; then
    ok "Reinstall detected — reusing existing takserver.env"
    TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2-)
    POSTGRES_USER=$(grep '^POSTGRES_USER=' "$ENV_FILE" | cut -d= -f2-)
    POSTGRES_DB=$(grep '^POSTGRES_DB=' "$ENV_FILE" | cut -d= -f2-)
    _TOTAL=3
    step "System Setup"
    if ! command -v docker &>/dev/null; then
        spin_start "Installing Docker"
        curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
        systemctl enable --now docker >/dev/null 2>&1
        spin_stop "Docker installed"
    else
        ok "Docker $(docker --version | awk '{print $3}' | tr -d ,) already installed"
    fi

    step "Building & Starting"
    cd "$SCRIPT_DIR"
    docker compose --env-file "$ENV_FILE" down --remove-orphans 2>/dev/null || true

    _BUILD_LOG=$(mktemp)
    spin_start "Building TAK Server image (this takes a few minutes)"
    if ! docker compose --env-file "$ENV_FILE" build > "$_BUILD_LOG" 2>&1; then
        spin_stop ""
        fail "Build failed — last 40 lines:\n$(tail -40 "$_BUILD_LOG")"
    fi
    spin_stop "Image built"
    rm -f "$_BUILD_LOG"

    spin_start "Starting containers"
    docker compose --env-file "$ENV_FILE" up -d
    spin_stop "Containers started"

    info "Waiting for database..."
    until docker compose --env-file "$ENV_FILE" exec -T takdb pg_isready -U "${POSTGRES_USER:-martiuser}" -d "${POSTGRES_DB:-cot}" >/dev/null 2>&1; do
        sleep 3
    done
    ok "Database ready"

    step "Done"
    printf "\n"
    printf "  ${G}┌─────────────────────────────────────────────────┐${NC}\n"
    printf "  ${G}│${NC}          ${W}TAK Server is starting up${NC}               ${G}│${NC}\n"
    printf "  ${G}└─────────────────────────────────────────────────┘${NC}\n"
    printf "\n"
    printf "  ${DIM}%-18s${NC}  %s\n" "SSL CoT"       "${TAK_SERVER_ADDRESS}:8089"
    printf "  ${DIM}%-18s${NC}  %s\n" "HTTPS API"     "https://${TAK_SERVER_ADDRESS}:8443"
    printf "  ${DIM}%-18s${NC}  %s\n" "Packages"      "http://${TAK_SERVER_ADDRESS}:8888/"
    printf "  ${DIM}%-18s${NC}  %s\n" "Admin panel"   "https://${TAK_SERVER_ADDRESS}:8889/"
    printf "\n"
    printf "  ${DIM}Logs:${NC}       docker compose logs -f\n"
    printf "\n"
    exit 0
fi

# ── [1/7] Networking ──────────────────────────────────────────────────────────
step "Networking"

TAK_SERVER_ADDRESS=""
_NB_IP=$(ip addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true
_TS_IP=$(ip addr show tailscale0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true

if [ -n "$_NB_IP" ] && [ -n "$_TS_IP" ]; then
    ok "NetBird: $_NB_IP"
    ok "Tailscale: $_TS_IP"
    pick _VPN "Select VPN to use:" "NetBird ($_NB_IP)" "Tailscale ($_TS_IP)"
    [[ "$_VPN" == Tailscale* ]] && TAK_SERVER_ADDRESS="$_TS_IP" || TAK_SERVER_ADDRESS="$_NB_IP"
elif [ -n "$_NB_IP" ]; then
    TAK_SERVER_ADDRESS="$_NB_IP"
    ok "NetBird detected — $_NB_IP"
elif [ -n "$_TS_IP" ]; then
    TAK_SERVER_ADDRESS="$_TS_IP"
    ok "Tailscale detected — $_TS_IP"
else
    warn "No VPN detected."
    pick _VPN_ACTION "How should remote devices reach this server?" \
        "Install NetBird (recommended)" \
        "Install Tailscale" \
        "Enter IP/hostname manually"

    case "$_VPN_ACTION" in
        "Install NetBird"*)
            ask_secret VPN_KEY "NetBird setup key (app.netbird.io → Keys)"
            spin_start "Installing NetBird"
            curl -fsSL https://pkgs.netbird.io/install.sh | sh >/dev/null 2>&1
            spin_stop "NetBird installed"
            spin_start "Connecting to NetBird"
            netbird up --setup-key="$VPN_KEY" >/dev/null 2>&1 \
                || { spin_stop ""; fail "NetBird connection failed — check your setup key"; }
            sleep 5
            TAK_SERVER_ADDRESS=$(ip addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            [ -n "$TAK_SERVER_ADDRESS" ] || fail "Could not read wt0 IP after connecting"
            spin_stop "NetBird connected — $TAK_SERVER_ADDRESS"
            ;;
        "Install Tailscale"*)
            ask_secret VPN_KEY "Tailscale auth key (login.tailscale.com → Settings → Keys)"
            spin_start "Installing Tailscale"
            curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1
            spin_stop "Tailscale installed"
            spin_start "Connecting to Tailscale"
            tailscale up --authkey="$VPN_KEY" >/dev/null 2>&1 \
                || { spin_stop ""; fail "Tailscale connection failed — check your auth key"; }
            sleep 5
            TAK_SERVER_ADDRESS=$(ip addr show tailscale0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            [ -n "$TAK_SERVER_ADDRESS" ] || fail "Could not read tailscale0 IP after connecting"
            spin_stop "Tailscale connected — $TAK_SERVER_ADDRESS"
            ;;
        *)
            ask TAK_SERVER_ADDRESS "Server IP or hostname" ""
            ;;
    esac
fi
ok "Server address: $TAK_SERVER_ADDRESS"

# ── [2/7] Certificate metadata ────────────────────────────────────────────────
step "Certificate Metadata"
dim "Used to generate the server and client TLS certificates."
ask COUNTRY             "Country code (2 letters)" "US"
ask STATE               "State / Province"         "Florida"
ask CITY                "City"                     "Tampa"
ask ORGANIZATION        "Organization"             "TAK Server"
ask ORGANIZATIONAL_UNIT "Organizational unit"      "Ops"

# ── [3/7] Admin panel ─────────────────────────────────────────────────────────
step "Admin Panel"
ask ADMIN_FIRST_USER "Admin username" "admin"
dim "Password must be at least 12 characters."
while true; do
    ask_secret ADMIN_FIRST_PASS "Admin password"
    [ ${#ADMIN_FIRST_PASS} -ge 12 ] && break
    warn "Password too short — minimum 12 characters."
done

# ── [4/7] Confirm ─────────────────────────────────────────────────────────────
step "Review"
printf "\n"
printf "  ${DIM}%-24s${NC} %s\n" "Server address"   "$TAK_SERVER_ADDRESS"
printf "  ${DIM}%-24s${NC} %s\n" "Country"           "$COUNTRY"
printf "  ${DIM}%-24s${NC} %s\n" "State"             "$STATE"
printf "  ${DIM}%-24s${NC} %s\n" "City"              "$CITY"
printf "  ${DIM}%-24s${NC} %s\n" "Organization"      "$ORGANIZATION"
printf "  ${DIM}%-24s${NC} %s\n" "Org unit"          "$ORGANIZATIONAL_UNIT"
printf "  ${DIM}%-24s${NC} %s\n" "Admin user"        "$ADMIN_FIRST_USER"
printf "  ${DIM}%-24s${NC} %s\n" "Admin password"    "(set)"
printf "  ${DIM}%-24s${NC} %s\n" "DB/cert passwords" "(auto-generated)"
printf "\n"
printf "     Proceed with installation? [Y/n]: "
read -r _CONFIRM
[[ "${_CONFIRM:-Y}" =~ ^[Yy] ]] || { echo "  Aborted."; exit 0; }

# ── [5/7] System setup ────────────────────────────────────────────────────────
step "System Setup"

if ! getent hosts debian.org >/dev/null 2>&1; then
    warn "DNS not resolving — adding fallback 1.1.1.1"
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    getent hosts debian.org >/dev/null 2>&1 || fail "DNS still broken — fix /etc/resolv.conf and retry"
    ok "DNS fallback working"
fi

if ! command -v docker &>/dev/null; then
    spin_start "Installing Docker"
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
    systemctl enable --now docker >/dev/null 2>&1
    spin_stop "Docker installed"
else
    ok "Docker $(docker --version | awk '{print $3}' | tr -d ,) already installed"
fi

[ -n "${SUDO_USER:-}" ] && { usermod -aG docker "$SUDO_USER"; ok "Added $SUDO_USER to docker group"; }

for kv in "net.ipv4.tcp_keepalive_time=60" "net.ipv4.tcp_keepalive_intvl=10" "net.ipv4.tcp_keepalive_probes=6"; do
    key="${kv%%=*}"; val="${kv##*=}"
    grep -qE "^${key}=" /etc/sysctl.conf 2>/dev/null \
        && sed -i "s|^${key}=.*|${key}=${val}|" /etc/sysctl.conf \
        || echo "${key}=${val}" >> /etc/sysctl.conf
done
sysctl -p >/dev/null 2>&1
ok "TCP keepalive configured (60s/10s/6)"

# ── [6/7] Write config ────────────────────────────────────────────────────────
step "Writing Configuration"

POSTGRES_PASSWORD=$(gen_hex 16)
ADMIN_CERT_PASS=$(gen_hex 16)
TAKSERVER_CERT_PASS=$(gen_hex 16)
CA_PASS=$(gen_hex 16)
ADMIN_SECRET_KEY=$(gen_hex 32)

cat > "$ENV_FILE" << ENVEOF
# TAK Server configuration — generated $(date -u '+%Y-%m-%d %H:%M UTC')
# DO NOT commit this file to version control.

TAK_SERVER_ADDRESS=${TAK_SERVER_ADDRESS}
TAK_SERVER_NAME=takserver

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
ok "takserver.env written"

# ── [7/7] Build & start ───────────────────────────────────────────────────────
step "Building & Starting"

cd "$SCRIPT_DIR"
docker compose --env-file "$ENV_FILE" down --remove-orphans 2>/dev/null || true

_BUILD_LOG=$(mktemp)
spin_start "Building TAK Server image (this takes a few minutes)"
if ! docker compose --env-file "$ENV_FILE" build > "$_BUILD_LOG" 2>&1; then
    spin_stop ""
    fail "Build failed — last 40 lines:\n$(tail -40 "$_BUILD_LOG")"
fi
spin_stop "Image built"
rm -f "$_BUILD_LOG"

spin_start "Starting containers"
docker compose --env-file "$ENV_FILE" up -d
spin_stop "Containers started"

info "Waiting for database..."
until docker compose --env-file "$ENV_FILE" exec -T takdb pg_isready -U martiuser -d cot >/dev/null 2>&1; do
    sleep 3
done
ok "Database ready"

ok "Initialization running in background (certs + DB schema, ~2 min)"
dim "Monitor: docker compose logs -f takserver_initialization"

# ── Done ─────────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${G}┌─────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}          ${W}TAK Server is starting up${NC}               ${G}│${NC}\n"
printf "  ${G}└─────────────────────────────────────────────────┘${NC}\n"
printf "\n"
printf "  ${DIM}%-18s${NC}  %s\n" "SSL CoT"       "${TAK_SERVER_ADDRESS}:8089"
printf "  ${DIM}%-18s${NC}  %s\n" "HTTPS API"     "https://${TAK_SERVER_ADDRESS}:8443"
printf "  ${DIM}%-18s${NC}  %s\n" "Packages"      "http://${TAK_SERVER_ADDRESS}:8888/"
printf "  ${DIM}%-18s${NC}  %s\n" "Admin panel"   "https://${TAK_SERVER_ADDRESS}:8889/"
printf "\n"
printf "  ${DIM}%-18s${NC}  ${W}%s${NC}\n" "Admin user"    "$ADMIN_FIRST_USER"
printf "  ${DIM}%-18s${NC}  ${W}%s${NC}\n" "Admin password" "$ADMIN_FIRST_PASS"
printf "\n"
printf "  ${DIM}Add users:${NC}  make add-user USERNAME=callsign\n"
printf "  ${DIM}Logs:${NC}       docker compose logs -f\n"
printf "\n"
