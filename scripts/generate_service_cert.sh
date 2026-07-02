#!/usr/bin/env bash
# Generate a client certificate for a machine service (e.g. EFDI moon-pod).
# Outputs PEM cert + key + CA cert to ./certs/<name>/ for use with Python ssl.
# Usage: ./generate_service_cert.sh [name]   (prompts interactively if omitted)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
WT_BACKTITLE="TAK Server — Service Cert"
# shellcheck source=_tui.sh
. "$SCRIPT_DIR/scripts/_tui.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

# ── Args ──────────────────────────────────────────────────────────────────────
NAME="${1:-}"
if [ -z "$NAME" ]; then
    while true; do
        wt_input_required NAME "New Service Cert" "Service name (e.g. efdi-pod):"
        [[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] && break
        wt_msg "Invalid name" "Only letters, numbers, hyphens, and underscores are allowed." 8 60
    done
elif [[ ! "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    fail "Name must contain only letters, numbers, hyphens, underscores"
fi

TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)
OUT_DIR="$SCRIPT_DIR/certs/$NAME"
mkdir -p "$OUT_DIR"

# ── Steps ─────────────────────────────────────────────────────────────────────
run_with_gauge "$NAME" "Generating certificate and data package..." -- \
    docker compose --env-file "$ENV_FILE" exec -T \
        -e CLIENT_CERT_NAME="$NAME" \
        -e TAK_SERVER_ADDRESS="$TAK_SERVER_ADDRESS" \
        takserver_config bash /opt/scripts/make_client_zip.sh \
    || fail "Certificate generation failed (see output above)."

run_with_gauge "$NAME" "Authorizing on server..." -- \
    docker compose --env-file "$ENV_FILE" exec -T \
        -e USER_CERT_NAME="$NAME" \
        takserver_config bash /opt/scripts/enable_user.sh \
    || fail "Authorization failed (see output above)."

_EXPORT_SCRIPT=$(mktemp)
cat > "$_EXPORT_SCRIPT" <<EOF
set -e
docker compose --env-file "$ENV_FILE" exec -T takserver_config bash -c "cat /opt/tak/data/certs/files/${NAME}.pem" > "$OUT_DIR/cert.pem"
docker compose --env-file "$ENV_FILE" exec -T takserver_config bash -c "cat /opt/tak/data/certs/files/${NAME}.key" > "$OUT_DIR/key.pem"
docker compose --env-file "$ENV_FILE" exec -T takserver_config bash -c "cat /opt/tak/data/certs/files/ca.pem" > "$OUT_DIR/ca.pem"
chmod 600 "$OUT_DIR/key.pem"
EOF
run_with_gauge "$NAME" "Exporting PEM files to host..." -- bash "$_EXPORT_SCRIPT" \
    || { rm -f "$_EXPORT_SCRIPT"; fail "Export failed (see output above)."; }
rm -f "$_EXPORT_SCRIPT"

# ── Summary ───────────────────────────────────────────────────────────────────
wt_msg "Service cert ready" "$OUT_DIR/\n\ncert.pem — client certificate\nkey.pem  — private key\nca.pem   — TAK Server CA\n\nmTLS (port 8089):\n  TAK_HOST=${TAK_SERVER_ADDRESS}  TAK_PORT=8089  TAK_TLS=1\n  TAK_CERT=${OUT_DIR}/cert.pem\n  TAK_KEY=${OUT_DIR}/key.pem\n  TAK_CA=${OUT_DIR}/ca.pem\n\nPlaintext (port 8087):\n  TAK_HOST=${TAK_SERVER_ADDRESS}  TAK_PORT=8087" 22 76

clear
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
