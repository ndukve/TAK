#!/usr/bin/env bash
# Generate a TAK client data package.
# Usage: ./generate_user.sh [callsign]   (prompts interactively if omitted)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

# ── Callsign ──────────────────────────────────────────────────────────────────
USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
    while true; do
        printf "  Callsign (letters, numbers, hyphens, underscores): "
        read -r USERNAME
        [[ "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]] && break
        printf "  ${R}Invalid — only letters, numbers, hyphens, underscores${NC}\n"
    done
elif [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    fail "Callsign must contain only letters, numbers, hyphens, underscores"
fi

TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)

DC="docker compose"
docker info &>/dev/null 2>&1 || DC="sudo docker compose"

banner "New User: $USERNAME"

# ── Steps ─────────────────────────────────────────────────────────────────────
run_spin "Generating device certificate" "Certificate generated" \
    $DC --env-file "$ENV_FILE" exec -T \
        -e CLIENT_CERT_NAME="$USERNAME" \
        takserver_config bash /opt/scripts/gen_client_cert.sh \
    || fail "Certificate generation failed (see output above)."

run_spin "Building data package" "Package built" \
    $DC --env-file "$ENV_FILE" exec -T \
        -e CLIENT_CERT_NAME="$USERNAME" \
        -e TAK_SERVER_ADDRESS="$TAK_SERVER_ADDRESS" \
        takserver_config bash /opt/scripts/make_pkg_zip.sh \
    || fail "Package build failed (see output above)."

run_spin "Authorizing on server" "Authorized" \
    $DC --env-file "$ENV_FILE" exec -T \
        -e USER_CERT_NAME="$USERNAME" \
        takserver_config bash /opt/scripts/enable_user.sh \
    || fail "Authorization failed (see output above)."

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
