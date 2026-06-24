#!/bin/bash
# Generate a TAK client data package (thin wrapper around make_client_zip.sh in container).
# Usage: ./generate_user.sh <username>

set -euo pipefail

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
    echo "Usage: $0 <username>" >&2
    exit 1
fi

if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: username must contain only letters, numbers, hyphens, and underscores" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"

[ -f "$ENV_FILE" ] || { echo "takserver.env not found — run ./install.sh first" >&2; exit 1; }

TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)

# Use sudo if the current user can't reach the Docker socket
DC="docker compose"
docker info &>/dev/null 2>&1 || DC="sudo docker compose"

$DC --env-file "$ENV_FILE" exec \
    -e CLIENT_CERT_NAME="$USERNAME" \
    -e TAK_SERVER_ADDRESS="$TAK_SERVER_ADDRESS" \
    takserver_config bash /opt/scripts/make_client_zip.sh

$DC --env-file "$ENV_FILE" exec \
    -e USER_CERT_NAME="$USERNAME" \
    takserver_config bash /opt/scripts/enable_user.sh

echo ""
echo "Package ready. Download on device:"
echo "  http://${TAK_SERVER_ADDRESS}:8888/${USERNAME}.zip"
echo ""
echo "Import in TAK client:"
echo "  iTAK : Settings → Network → Servers → + → Upload Server Package"
echo "  ATAK : Hamburger → Settings → Network Preferences → TAK Servers → + → Import"
echo "  WinTAK: Settings → Network Preferences → Server Connections → + → Import"
