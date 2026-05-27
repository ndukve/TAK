#!/bin/bash
# Pull latest config from git and rebuild the container.
# Run from the repo directory: ./update.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${CYAN}[*]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

[ -f "$ENV_FILE" ] || err ".env not found — run ./install.sh first"
[ -d "$SCRIPT_DIR/.git" ] || err "Not a git repo. Clone via git, not manual download."

cd "$SCRIPT_DIR"

info "Pulling latest changes..."
git pull --ff-only || err "git pull failed. Resolve conflicts manually."
ok "Up to date: $(git log -1 --format='%h %s')"

info "Rebuilding image..."
docker compose --env-file "$ENV_FILE" build --quiet
ok "Image rebuilt"

info "Restarting container..."
docker compose --env-file "$ENV_FILE" up -d
ok "Container restarted"

info "Syncing Web UI API token..."
_raw_api_key=$(grep '^FTS_API_KEY=' "$ENV_FILE" | cut -d= -f2)
if [ -n "$_raw_api_key" ]; then
    cat > /tmp/sync_token.py << 'PYEOF'
import sqlite3, os
key = os.environ['_K']
con = sqlite3.connect('/opt/fts/FTSDataBase.db')
con.execute('UPDATE SystemUser SET token=? WHERE name=?', (key, 'admin'))
con.commit()
PYEOF
    docker cp /tmp/sync_token.py freetakserver:/tmp/sync_token.py
    docker exec -e _K="$_raw_api_key" freetakserver python3 /tmp/sync_token.py \
        && ok "Web UI API token synced" \
        || warn "Could not sync Web UI token"
fi

echo ""
echo -e "  ${BOLD}Done.${NC} View logs: docker logs freetakserver -f"
