#!/usr/bin/env bash
# Generate a TAK client data package.
# Usage: ./generate_user.sh [callsign]   (prompts interactively if omitted)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
WT_BACKTITLE="TAK Server — New User"
# shellcheck source=scripts/_tui.sh
. "$SCRIPT_DIR/scripts/_tui.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

# ── Callsign ──────────────────────────────────────────────────────────────────
USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
    while true; do
        wt_input_required USERNAME "New TAK User" "Callsign (letters, numbers, hyphens, underscores):"
        [[ "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]] && break
        wt_msg "Invalid callsign" "Only letters, numbers, hyphens, and underscores are allowed." 8 60
    done
elif [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    fail "Callsign must contain only letters, numbers, hyphens, underscores"
fi

TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)

DC="docker compose"
docker info &>/dev/null 2>&1 || DC="sudo docker compose"

# ── Steps ─────────────────────────────────────────────────────────────────────
run_with_gauge "New User: $USERNAME" "Generating device certificate..." -- \
    $DC --env-file "$ENV_FILE" exec -T \
        -e CLIENT_CERT_NAME="$USERNAME" \
        takserver_config bash /opt/scripts/gen_client_cert.sh \
    || fail "Certificate generation failed (see output above)."

run_with_gauge "New User: $USERNAME" "Building data package..." -- \
    $DC --env-file "$ENV_FILE" exec -T \
        -e CLIENT_CERT_NAME="$USERNAME" \
        -e TAK_SERVER_ADDRESS="$TAK_SERVER_ADDRESS" \
        takserver_config bash /opt/scripts/make_pkg_zip.sh \
    || fail "Package build failed (see output above)."

run_with_gauge "New User: $USERNAME" "Authorizing on server..." -- \
    $DC --env-file "$ENV_FILE" exec -T \
        -e USER_CERT_NAME="$USERNAME" \
        takserver_config bash /opt/scripts/enable_user.sh \
    || fail "Authorization failed (see output above)."

# ── Summary ───────────────────────────────────────────────────────────────────
wt_msg "$USERNAME is ready" "Download: http://${TAK_SERVER_ADDRESS}:8888/${USERNAME}.zip\n\nImport in TAK client:\n  iTAK  : Settings -> Network -> Servers -> + -> Upload Server Package\n  ATAK  : Hamburger -> Settings -> Network Prefs -> TAK Servers -> Import\n  WinTAK: Settings -> Network Prefs -> Server Connections -> Import" 18 74

clear
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
