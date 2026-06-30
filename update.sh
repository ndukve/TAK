#!/bin/bash
# Pull latest config from git and rebuild the containers.
# Run from the repo directory: ./update.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${CYAN}[*]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

[ -f "$ENV_FILE" ] || err "takserver.env not found — run ./install.sh first"
[ -d "$SCRIPT_DIR/.git" ] || err "Not a git repo. Clone via git, not manual download."

cd "$SCRIPT_DIR"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
info "Fetching latest changes..."
git fetch origin "$BRANCH" || err "git fetch failed. Check network/remote."
info "Overwriting local changes with origin/$BRANCH..."
git reset --hard "origin/$BRANCH" || err "git reset failed."
ok "Up to date: $(git log -1 --format='%h %s')"

info "Checking for new required env vars..."
backfill_var() {
  local key="$1" val="$2"
  if ! grep -q "^${key}=" "$ENV_FILE"; then
    echo "${key}=${val}" >> "$ENV_FILE"
    ok "Added ${key} to takserver.env"
  fi
}
backfill_var "ADMIN_SECRET_KEY"  "$(openssl rand -hex 32)"
backfill_var "ADMIN_FIRST_USER"  "admin"
backfill_var "ADMIN_FIRST_PASS"  "$(openssl rand -base64 16 | tr -d '/+=' | head -c 20)"

info "Rebuilding image..."
docker compose --env-file "$ENV_FILE" build --quiet
ok "Image rebuilt"

info "Restarting containers..."
docker compose --env-file "$ENV_FILE" down --remove-orphans
docker compose --env-file "$ENV_FILE" up -d
ok "Containers restarted"

echo ""
echo -e "  ${BOLD}Done.${NC} View logs: docker compose --env-file takserver.env logs -f"
