#!/usr/bin/env bash
# Wipe containers/images and reinstall from scratch.
# Preserves: database volumes, certificates, packages, takserver.env
# Wipes: Docker images and containers (forces full rebuild)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Style ─────────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m'
W='\033[1;37m' DIM='\033[2m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*"; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }
warn() { printf "${Y}  !${NC}  %s\n" "$*"; }

_SP_PID=""; _SP_START=0
_SP_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
spin_start() {
    _SP_START=$(date +%s)
    ( local i=0
      while true; do
          printf "\r  ${C}%s${NC}  %s  ${DIM}%ds${NC}" \
              "${_SP_FRAMES[$((i % ${#_SP_FRAMES[@]}))]}" "$1" "$(( $(date +%s) - _SP_START ))"
          sleep 0.1; i=$(( i + 1 ))
      done ) &
    _SP_PID=$!
}
spin_stop() {
    [ -n "$_SP_PID" ] && { kill "$_SP_PID" 2>/dev/null; wait "$_SP_PID" 2>/dev/null; _SP_PID=""; }
    printf "\r\033[K"
    ok "$1 ${DIM}($(( $(date +%s) - _SP_START ))s)${NC}"
}
trap '[ -n "$_SP_PID" ] && kill "$_SP_PID" 2>/dev/null; printf "\r\033[K"' EXIT

# ── Warning ───────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${W}TAK Server — Reinstall${NC}\n"
printf "  %s\n\n" "$(printf '─%.0s' {1..48})"
warn "This will stop and remove all containers and images."
warn "A full rebuild will run (same as a fresh install)."
printf "\n"
printf "  ${G}Preserved:${NC}  database, certificates, packages, takserver.env\n"
printf "  ${R}Removed:${NC}    Docker images and containers\n"
printf "\n"
printf "  Continue? [y/N]: "
read -r _CONFIRM
[[ "${_CONFIRM:-N}" =~ ^[Yy]$ ]] || { printf "  Aborted.\n"; exit 0; }
printf "\n"

# ── Wipe ─────────────────────────────────────────────────────────────────────
spin_start "Stopping containers and removing images"
docker compose down --remove-orphans --rmi local 2>/dev/null || true
spin_stop "Containers and images removed"

# ── Reinstall ────────────────────────────────────────────────────────────────
printf "\n"
exec bash "$SCRIPT_DIR/install.sh"
