#!/usr/bin/env bash
# Pull latest changes from git and rebuild containers.
# Run from the repo directory: ./update.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"

# ── Style ─────────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' C='\033[0;36m' W='\033[1;37m' DIM='\033[2m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*"; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }
dim()  { printf "${DIM}     %s${NC}\n" "$*"; }

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

# ── Preflight ─────────────────────────────────────────────────────────────────
[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"
[ -d "$SCRIPT_DIR/.git" ] || fail "Not a git repo — clone via git, not manual download"

printf "\n  ${W}TAK Server — Update${NC}\n"
printf "  %s\n\n" "$(printf '─%.0s' {1..48})"

cd "$SCRIPT_DIR"

# ── Pull ──────────────────────────────────────────────────────────────────────
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "HEAD" ] && fail "Repo is in detached HEAD state — run: git checkout main"
_OLD_HEAD="$(git rev-parse HEAD)"
spin_start "Fetching latest changes (branch: $BRANCH)"
git fetch origin "$BRANCH" 2>/dev/null || { spin_stop ""; fail "git fetch failed — check network/remote"; }
git reset --hard "origin/$BRANCH" 2>/dev/null || { spin_stop ""; fail "git reset failed"; }
spin_stop "Up to date: $(git log -1 --format='%h %s')"

if [ "$_OLD_HEAD" != "$(git rev-parse HEAD)" ]; then
    git --no-pager diff --stat "$_OLD_HEAD" HEAD
    printf "\n"
else
    dim "No changes — already up to date."
fi

# ── Backfill env vars ─────────────────────────────────────────────────────────
info "Checking for missing env vars..."
backfill() {
    local key="$1" val="$2"
    if ! grep -q "^${key}=" "$ENV_FILE"; then
        echo "${key}=${val}" >> "$ENV_FILE"
        ok "Added ${key}"
    fi
}
backfill "ADMIN_SECRET_KEY" "$(openssl rand -hex 32)"
backfill "ADMIN_FIRST_USER" "admin"
backfill "ADMIN_FIRST_PASS" "$(openssl rand -base64 16 | tr -d '/+=' | head -c 20)"

# ── Admin DB ──────────────────────────────────────────────────────────────────
info "Ensuring admin database exists..."
PGUSER=$(grep '^POSTGRES_USER=' "$ENV_FILE" | cut -d= -f2)
PGUSER="${PGUSER:-martiuser}"
docker compose exec -T takdb psql -U "$PGUSER" \
    -c "CREATE DATABASE admin;" 2>/dev/null \
    && ok "admin database created" \
    || ok "admin database already exists"

# ── Rebuild ───────────────────────────────────────────────────────────────────
_BUILD_LOG=$(mktemp)
spin_start "Building updated image"
if ! docker compose --env-file "$ENV_FILE" build > "$_BUILD_LOG" 2>&1; then
    spin_stop ""
    fail "Build failed — last 40 lines:\n$(tail -40 "$_BUILD_LOG")"
fi
spin_stop "Image built"
rm -f "$_BUILD_LOG"

spin_start "Restarting containers"
docker compose --env-file "$ENV_FILE" down --remove-orphans
docker compose --env-file "$ENV_FILE" up -d
spin_stop "Containers restarted"

# ── Done ──────────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}  ${W}Update complete${NC}                              ${G}│${NC}\n"
printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
printf "\n"
printf "  ${DIM}Logs:${NC}  docker compose --env-file takserver.env logs -f\n"
printf "\n"
