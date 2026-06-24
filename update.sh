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

info "Pulling latest changes..."
git pull --ff-only || err "git pull failed. Resolve conflicts manually."
git submodule update --init --recursive
ok "Up to date: $(git log -1 --format='%h %s')"

info "Rebuilding image..."
docker compose --env-file "$ENV_FILE" build --quiet
ok "Image rebuilt"

info "Restarting containers..."
docker compose --env-file "$ENV_FILE" down --remove-orphans
docker compose --env-file "$ENV_FILE" up -d
ok "Containers restarted"

echo ""
echo -e "  ${BOLD}Done.${NC} View logs: docker compose --env-file takserver.env logs -f"
