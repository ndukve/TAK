#!/bin/bash
# Generate a client certificate for a machine service (e.g. EFDI moon-pod).
# Outputs PEM cert + key + CA cert to ./certs/<name>/ for use with Python ssl.
# Usage: ./generate_service_cert.sh <name>

set -euo pipefail

NAME="${1:-}"
if [ -z "$NAME" ]; then
    echo "Usage: $0 <service-name>  (e.g. efdi-pod)" >&2
    exit 1
fi

if [[ ! "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: name must contain only letters, numbers, hyphens, and underscores" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
OUT_DIR="$SCRIPT_DIR/certs/$NAME"

[ -f "$ENV_FILE" ] || { echo "takserver.env not found — run ./install.sh first" >&2; exit 1; }

TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)

mkdir -p "$OUT_DIR"

# Generate client cert inside the config container
docker compose --env-file "$ENV_FILE" exec \
    -e CLIENT_CERT_NAME="$NAME" \
    -e TAK_SERVER_ADDRESS="$TAK_SERVER_ADDRESS" \
    takserver_config bash /opt/scripts/make_client_zip.sh

# Register cert with UserManager
docker compose --env-file "$ENV_FILE" exec \
    -e USER_CERT_NAME="$NAME" \
    takserver_config bash /opt/scripts/enable_user.sh

# Export PEM cert, key, and CA cert to host
docker compose --env-file "$ENV_FILE" exec takserver_config \
    bash -c "cat /opt/tak/data/certs/files/${NAME}.pem" > "$OUT_DIR/cert.pem"

docker compose --env-file "$ENV_FILE" exec takserver_config \
    bash -c "cat /opt/tak/data/certs/files/${NAME}.key" > "$OUT_DIR/key.pem"

docker compose --env-file "$ENV_FILE" exec takserver_config \
    bash -c "cat /opt/tak/data/certs/files/ca.pem" > "$OUT_DIR/ca.pem"

chmod 600 "$OUT_DIR/key.pem"

echo ""
echo "Service cert ready: $OUT_DIR/"
echo ""
echo "  cert.pem  — client certificate"
echo "  key.pem   — private key"
echo "  ca.pem    — TAK Server CA (trust anchor)"
echo ""
echo "EFDI .env configuration (Option B — mTLS on port 8089):"
echo ""
echo "  TAK_HOST=$TAK_SERVER_ADDRESS"
echo "  TAK_PORT=8089"
echo "  TAK_TLS=1"
echo "  TAK_CERT=$OUT_DIR/cert.pem"
echo "  TAK_KEY=$OUT_DIR/key.pem"
echo "  TAK_CA=$OUT_DIR/ca.pem"
echo ""
echo "EFDI .env configuration (Option A — plaintext on port 8087):"
echo ""
echo "  TAK_HOST=$TAK_SERVER_ADDRESS"
echo "  TAK_PORT=8087"
