#!/usr/bin/env bash
# Verify the deployed basemap path from admin authentication through a real,
# TLS-validated tile response. This does not require an ATAK device.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${TAK_ENV_FILE:-$SCRIPT_DIR/takserver.env}"

if [ ! -f "$ENV_FILE" ]; then
    printf 'Environment file not found: %s\n' "$ENV_FILE" >&2
    exit 1
fi

SERVER_ADDRESS="$(sed -n 's/^TAK_SERVER_ADDRESS=//p' "$ENV_FILE" | head -1)"
ADMIN_URL="${1:-https://${SERVER_ADDRESS}:8889}"
ADMIN_USER="${2:-admin}"
if [ -z "$SERVER_ADDRESS" ]; then
    printf 'TAK_SERVER_ADDRESS is empty in %s\n' "$ENV_FILE" >&2
    exit 1
fi

read -r -s -p "Admin password for ${ADMIN_USER}: " ADMIN_PASSWORD
printf '\n'
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

docker compose --env-file "$ENV_FILE" exec -T takserver_config \
    cat /opt/tak/data/certs/files/root-ca.pem >"$TEMP_DIR/root-ca.pem"

LOGIN_JSON="$(
    ADMIN_USER="$ADMIN_USER" ADMIN_PASSWORD="$ADMIN_PASSWORD" python3 -c \
        'import json, os; print(json.dumps({"username": os.environ["ADMIN_USER"], "password": os.environ["ADMIN_PASSWORD"]}))'
)"
LOGIN_RESPONSE="$(curl --fail-with-body --silent --show-error \
    --cacert "$TEMP_DIR/root-ca.pem" \
    -H 'Content-Type: application/json' \
    --data "$LOGIN_JSON" \
    "$ADMIN_URL/auth/login")"
ACCESS_TOKEN="$(printf '%s' "$LOGIN_RESPONSE" | python3 -c 'import json, sys; print(json.load(sys.stdin)["access_token"])')"

curl --fail-with-body --silent --show-error \
    --cacert "$TEMP_DIR/root-ca.pem" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$ADMIN_URL/api/basemaps/diagnostics" >"$TEMP_DIR/diagnostics.json"

READY="$(python3 -c 'import json, sys; print(str(json.load(open(sys.argv[1]))["ready"]).lower())' "$TEMP_DIR/diagnostics.json")"
if [ "$READY" != "true" ]; then
    python3 -m json.tool "$TEMP_DIR/diagnostics.json"
    printf 'Basemap diagnostics are not ready.\n' >&2
    exit 1
fi

SAMPLE_TILE_URL="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["sample_tile_url"])' "$TEMP_DIR/diagnostics.json")"
CONTENT_TYPE="$(curl --fail-with-body --silent --show-error \
    --cacert "$TEMP_DIR/root-ca.pem" \
    --output "$TEMP_DIR/tile" \
    --write-out '%{content_type}' \
    "$SAMPLE_TILE_URL")"
case "$CONTENT_TYPE" in
    image/png|image/jpeg) ;;
    *)
        printf 'Tile proxy returned unexpected content type: %s\n' "$CONTENT_TYPE" >&2
        exit 1
        ;;
esac

printf 'Basemap smoke test passed: TAK API, service certificate, cache, proxy TLS, and upstream tile are working.\n'
