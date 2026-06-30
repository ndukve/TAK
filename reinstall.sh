#!/bin/bash
# Wipe install artifacts and reinstall, preserving user data.
# Keeps: database, certificates, packages, takserver.env
# Wipes: Docker images and containers (forces full rebuild)
# Run from the repo directory as root: ./reinstall.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${YELLOW}${BOLD}This will rebuild all containers and images.${NC}"
echo -e "${YELLOW}User data (certs, packages, database accounts) will be preserved.${NC}"
echo ""
read -rp "Continue? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

echo ""
echo "[*] Stopping containers and removing images (volumes kept)..."
docker compose down --remove-orphans --rmi local 2>/dev/null || true

echo "[*] Rebuilding and starting..."
exec bash "$SCRIPT_DIR/install.sh"
