#!/usr/bin/env bash
# Pull latest changes from git and rebuild containers.
# Run from the repo directory: ./update.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

# ── Preflight ─────────────────────────────────────────────────────────────────
[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"
[ -d "$SCRIPT_DIR/.git" ] || fail "Not a git repo — clone via git, not manual download"

banner "Update"
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
run_spin "Building updated image" "Image built" \
    docker compose --env-file "$ENV_FILE" build \
    || fail "Build failed (see output above)."

run_spin "Restarting containers" "Containers restarted" bash -c \
    "docker compose --env-file '$ENV_FILE' down --remove-orphans && docker compose --env-file '$ENV_FILE' up -d" \
    || fail "Container restart failed (see output above)."

# ── Done ──────────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}  ${W}Update complete${NC}                              ${G}│${NC}\n"
printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
printf "\n"
printf "  ${DIM}Logs:${NC}  docker compose --env-file takserver.env logs -f\n"
printf "\n"
