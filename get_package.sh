#!/usr/bin/env bash
# Break-glass fallback: retrieve a package directly from the server, without
# needing the admin panel to be up. Requires SSH/shell access to the server
# itself — this is not a network service, nothing for an unauthenticated
# party to reach. Run with no argument to list what's available.
# Usage: ./get_package.sh [name]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

NAME="${1:-}"

if [ -z "$NAME" ]; then
    info "Available packages:"
    docker compose --env-file "$ENV_FILE" exec -T takserver_config \
        bash -c "ls /opt/tak/data/certs/files/clientpkgs/*.zip 2>/dev/null | xargs -n1 basename" \
        || warn "No packages found."
    exit 0
fi

DEST="./${NAME}.zip"
[ ! -f "$DEST" ] || fail "$DEST already exists in the current directory — remove it first or run this from elsewhere."

docker compose --env-file "$ENV_FILE" exec -T takserver_config \
    bash -c 'cat "/opt/tak/data/certs/files/clientpkgs/$1.zip"' -- "$NAME" > "$DEST" \
    || { rm -f "$DEST"; fail "Package '$NAME' not found."; }

ok "Saved to ${DEST}"
