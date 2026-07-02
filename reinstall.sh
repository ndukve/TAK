#!/usr/bin/env bash
# Wipe containers/images and reinstall from scratch.
# Preserves: database volumes, certificates, packages, takserver.env
# Wipes: Docker images and containers (forces full rebuild)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WT_BACKTITLE="TAK Server Reinstall"
# shellcheck source=scripts/_tui.sh
. "$SCRIPT_DIR/scripts/_tui.sh"

if ! wt_yesno "Reinstall" \
"This will stop and remove all containers and images, then run a full rebuild (same as a fresh install).

Preserved : database, certificates, packages, takserver.env
Removed   : Docker images and containers

Continue?" 16 72; then
    clear; echo "Aborted."; exit 0
fi

clear
printf "\n  ${W}TAK Server — Reinstall${NC}\n\n"

run_with_gauge "Reinstall" "Stopping containers and removing images..." -- bash -c \
    "docker compose down --remove-orphans --rmi local" || true
ok "Containers and images removed"

printf "\n"
exec env TAK_REINSTALL=1 bash "$SCRIPT_DIR/install.sh"
