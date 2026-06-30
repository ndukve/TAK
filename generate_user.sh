#!/usr/bin/env bash
# Generate a TAK client data package.
# Usage: ./generate_user.sh <username>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"

# ── Style ─────────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' C='\033[0;36m' W='\033[1;37m' DIM='\033[2m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*"; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }
dim()  { printf "${DIM}     %s${NC}\n" "$*"; }

_SP_PID=""; _SP_START=0
_SP_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
spin_start() {
    _SP_START=$(date +%s)
    ( local i=0
      while true; do
          printf "\r  ${C}%s${NC}  %s  ${DIM}%ds${NC}" \
              "${_SP_FRAMES[$((i % ${#_SP_FRAMES[@]}))]}" "$1" "$(( $(date +%s) - _SP_START ))"
          sleep 0.1; i=$(( i + 1 ))
      done ) &
    _SP_PID=$!
}
spin_stop() {
    [ -n "$_SP_PID" ] && { kill "$_SP_PID" 2>/dev/null; wait "$_SP_PID" 2>/dev/null; _SP_PID=""; }
    printf "\r\033[K"
    ok "$1 ${DIM}($(( $(date +%s) - _SP_START ))s)${NC}"
}
trap '[ -n "$_SP_PID" ] && kill "$_SP_PID" 2>/dev/null; printf "\r\033[K"' EXIT

# ── Args ──────────────────────────────────────────────────────────────────────
USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
    printf "  Usage: %s <callsign>\n" "$0" >&2; exit 1
fi
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    fail "Callsign must contain only letters, numbers, hyphens, underscores"
fi

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"
TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)

DC="docker compose"
docker info &>/dev/null 2>&1 || DC="sudo docker compose"

printf "\n  ${W}Creating TAK user:${NC} ${C}%s${NC}\n" "$USERNAME"
printf "  %s\n\n" "$(printf '─%.0s' {1..48})"

# ── Steps ─────────────────────────────────────────────────────────────────────
spin_start "Generating device certificate"
$DC --env-file "$ENV_FILE" exec -T \
    -e CLIENT_CERT_NAME="$USERNAME" \
    takserver_config bash /opt/scripts/gen_client_cert.sh >/dev/null
spin_stop "Certificate generated"

spin_start "Building data package"
$DC --env-file "$ENV_FILE" exec -T \
    -e CLIENT_CERT_NAME="$USERNAME" \
    -e TAK_SERVER_ADDRESS="$TAK_SERVER_ADDRESS" \
    takserver_config bash /opt/scripts/make_pkg_zip.sh >/dev/null
spin_stop "Package built"

spin_start "Authorizing on server"
$DC --env-file "$ENV_FILE" exec -T \
    -e USER_CERT_NAME="$USERNAME" \
    takserver_config bash /opt/scripts/enable_user.sh >/dev/null
spin_stop "Authorized"

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}  ${W}%s${NC} is ready                              ${G}│${NC}\n" "$USERNAME"
printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
printf "\n"
printf "  ${DIM}Download:${NC}  http://${TAK_SERVER_ADDRESS}:8888/${USERNAME}.zip\n"
printf "\n"
printf "  ${DIM}Import in TAK client:${NC}\n"
printf "  ${DIM}  iTAK  :${NC}  Settings → Network → Servers → + → Upload Server Package\n"
printf "  ${DIM}  ATAK  :${NC}  Hamburger → Settings → Network Preferences → TAK Servers → Import\n"
printf "  ${DIM}  WinTAK:${NC}  Settings → Network Preferences → Server Connections → Import\n"
printf "\n"
