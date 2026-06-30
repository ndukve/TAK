#!/usr/bin/env bash
# Generate a client certificate for a machine service (e.g. EFDI moon-pod).
# Outputs PEM cert + key + CA cert to ./certs/<name>/ for use with Python ssl.
# Usage: ./generate_service_cert.sh <name>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"

# ── Style ─────────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' C='\033[0;36m' W='\033[1;37m' DIM='\033[2m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

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
NAME="${1:-}"
[ -n "$NAME" ] || { printf "  Usage: %s <service-name>  (e.g. efdi-pod)\n" "$0" >&2; exit 1; }
[[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Name must contain only letters, numbers, hyphens, underscores"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)
OUT_DIR="$SCRIPT_DIR/certs/$NAME"

printf "\n  ${W}Generating service cert:${NC} ${C}%s${NC}\n" "$NAME"
printf "  %s\n\n" "$(printf '─%.0s' {1..48})"

mkdir -p "$OUT_DIR"

# ── Steps ─────────────────────────────────────────────────────────────────────
spin_start "Generating certificate and data package"
docker compose --env-file "$ENV_FILE" exec -T \
    -e CLIENT_CERT_NAME="$NAME" \
    -e TAK_SERVER_ADDRESS="$TAK_SERVER_ADDRESS" \
    takserver_config bash /opt/scripts/make_client_zip.sh >/dev/null
spin_stop "Certificate and package generated"

spin_start "Authorizing on server"
docker compose --env-file "$ENV_FILE" exec -T \
    -e USER_CERT_NAME="$NAME" \
    takserver_config bash /opt/scripts/enable_user.sh >/dev/null
spin_stop "Authorized"

spin_start "Exporting PEM files to host"
docker compose --env-file "$ENV_FILE" exec -T takserver_config \
    bash -c "cat /opt/tak/data/certs/files/${NAME}.pem" > "$OUT_DIR/cert.pem"
docker compose --env-file "$ENV_FILE" exec -T takserver_config \
    bash -c "cat /opt/tak/data/certs/files/${NAME}.key" > "$OUT_DIR/key.pem"
docker compose --env-file "$ENV_FILE" exec -T takserver_config \
    bash -c "cat /opt/tak/data/certs/files/ca.pem" > "$OUT_DIR/ca.pem"
chmod 600 "$OUT_DIR/key.pem"
spin_stop "PEM files exported"

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}  ${W}Service cert ready:${NC} %-28s${G}│${NC}\n" "$OUT_DIR/"
printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
printf "\n"
printf "  ${DIM}cert.pem${NC}  — client certificate\n"
printf "  ${DIM}key.pem${NC}   — private key\n"
printf "  ${DIM}ca.pem${NC}    — TAK Server CA (trust anchor)\n"
printf "\n"
printf "  ${W}mTLS (port 8089):${NC}\n"
printf "  ${DIM}  TAK_HOST=${NC}%s\n" "$TAK_SERVER_ADDRESS"
printf "  ${DIM}  TAK_PORT=${NC}8089  ${DIM}TAK_TLS=${NC}1\n"
printf "  ${DIM}  TAK_CERT=${NC}%s/cert.pem\n" "$OUT_DIR"
printf "  ${DIM}  TAK_KEY=${NC}%s/key.pem\n" "$OUT_DIR"
printf "  ${DIM}  TAK_CA=${NC}%s/ca.pem\n" "$OUT_DIR"
printf "\n"
printf "  ${W}Plaintext (port 8087):${NC}\n"
printf "  ${DIM}  TAK_HOST=${NC}%s  ${DIM}TAK_PORT=${NC}8087\n" "$TAK_SERVER_ADDRESS"
printf "\n"
