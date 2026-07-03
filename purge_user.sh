#!/usr/bin/env bash
# Force-remove all cert/package files for a user, regardless of current state.
# Use this to clean up leftovers from a user that was only revoked (not fully
# deleted) before delete_user.sh was fixed, or any other stuck state.
# Usage: ./purge_user.sh <name>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"
NAME="${1:-}"
[ -n "$NAME" ] || fail "Usage: $0 <name>"

CR=/opt/tak/data/certs
FILES=(
    "$CR/files/$NAME.certpass"
    "$CR/files/$NAME.p12"
    "$CR/files/$NAME.pem"
    "$CR/files/$NAME.key"
    "$CR/files/$NAME.csr"
    "$CR/files/$NAME.jks"
    "$CR/files/$NAME-public.p12"
    "$CR/files/$NAME-trusted.pem"
    "$CR/files/clientpkgs/$NAME.zip"
)

docker compose --env-file "$ENV_FILE" exec -T -u root takserver_config rm -f "${FILES[@]}"
ok "${NAME} purged"
