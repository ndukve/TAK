#!/usr/bin/env bash
# Generate a client certificate for a machine service (e.g. a sensor bridge).
# Outputs PEM cert + key + CA cert to ./certs/<name>/ for use with Python ssl.
# Usage: ./generate_service_cert.sh [name]   (prompts interactively if omitted)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

# ── Args ──────────────────────────────────────────────────────────────────────
NAME="${1:-}"
if [ -z "$NAME" ]; then
    while true; do
        printf "  Service name (e.g. sensor-bridge): "
        read -r NAME
        [[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] && break
        printf "  ${R}Invalid — only letters, numbers, hyphens, underscores${NC}\n"
    done
elif [[ ! "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    fail "Name must contain only letters, numbers, hyphens, underscores"
fi

TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)
OUT_DIR="$SCRIPT_DIR/certs/$NAME"
mkdir -p "$OUT_DIR"

banner "Service Cert: $NAME"

# ── Steps ─────────────────────────────────────────────────────────────────────
# Uses gen_client_cert.sh (not make_client_zip.sh) because it persists the key's
# encryption password to a .certpass file — needed below to decrypt the key for
# non-interactive services (Python ssl, etc. can't handle an encrypted PEM key).
run_spin "Generating certificate" "Certificate generated" \
    docker compose --env-file "$ENV_FILE" exec -T \
        -e CLIENT_CERT_NAME="$NAME" \
        takserver_config bash /opt/scripts/gen_client_cert.sh \
    || fail "Certificate generation failed (see output above)."

run_spin "Authorizing on server" "Authorized" \
    docker compose --env-file "$ENV_FILE" exec -T \
        -e USER_CERT_NAME="$NAME" \
        takserver_config bash /opt/scripts/enable_user.sh \
    || fail "Authorization failed (see output above)."

_EXPORT_SCRIPT=$(mktemp)
cat > "$_EXPORT_SCRIPT" <<EOF
set -e
docker compose --env-file "$ENV_FILE" exec -T takserver_config bash -c "cat /opt/tak/data/certs/files/${NAME}.pem" > "$OUT_DIR/cert.pem"
docker compose --env-file "$ENV_FILE" exec -T takserver_config bash -c "cat /opt/tak/data/certs/files/ca.pem" > "$OUT_DIR/ca.pem"
docker compose --env-file "$ENV_FILE" exec -T takserver_config bash -c '
    PASS=\$(cat /opt/tak/data/certs/files/${NAME}.certpass)
    openssl pkey -in /opt/tak/data/certs/files/${NAME}.key -passin pass:"\$PASS"
' > "$OUT_DIR/key.pem"
chmod 600 "$OUT_DIR/key.pem"
EOF
run_spin "Exporting PEM files (decrypting key)" "PEM files exported" bash "$_EXPORT_SCRIPT" \
    || { rm -f "$_EXPORT_SCRIPT"; fail "Export failed (see output above)."; }
rm -f "$_EXPORT_SCRIPT"

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}  ${W}Service cert ready:${NC} %-28s${G}│${NC}\n" "$OUT_DIR/"
printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
printf "\n"
printf "  ${DIM}cert.pem${NC}  — client certificate\n"
printf "  ${DIM}key.pem${NC}   — private key (decrypted, chmod 600)\n"
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
