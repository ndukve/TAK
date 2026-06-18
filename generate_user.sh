#!/bin/bash
# Generate a TAK client data package (thin wrapper around make_client_zip.sh in container).
# Usage: ./generate_user.sh <username>

set -euo pipefail

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
    echo "Usage: $0 <username>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"

[ -f "$ENV_FILE" ] || { echo "takserver.env not found — run ./install.sh first" >&2; exit 1; }

docker exec -e CLIENT_CERT_NAME="$USERNAME" tak-takserver_config-1 bash /opt/scripts/make_client_zip.sh

TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)

echo ""
echo "Package ready. Download on device:"
echo "  http://${TAK_SERVER_ADDRESS}:8888/${USERNAME}.zip"
echo ""
echo "Import in TAK client:"
echo "  iTAK : Settings → Network → Servers → + → Upload Server Package"
echo "  ATAK : Hamburger → Settings → Network Preferences → TAK Servers → + → Import"
echo "  WinTAK: Settings → Network Preferences → Server Connections → + → Import"
