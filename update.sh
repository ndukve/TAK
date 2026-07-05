#!/usr/bin/env bash
# Pull latest changes from git and rebuild containers.
# Run from the repo directory: ./update.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"
# shellcheck source=scripts/_selftest.sh
. "$SCRIPT_DIR/scripts/_selftest.sh"
# shellcheck source=scripts/refresh_vendor.sh
. "$SCRIPT_DIR/scripts/refresh_vendor.sh"

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
_PULL_LOG="$(mktemp)"
if ! git fetch origin "$BRANCH" > "$_PULL_LOG" 2>&1; then
    spin_stop ""
    cat "$_PULL_LOG"
    rm -f "$_PULL_LOG"
    fail "git fetch failed — check network/remote (output above)"
fi
if ! git reset --hard "origin/$BRANCH" >> "$_PULL_LOG" 2>&1; then
    spin_stop ""
    cat "$_PULL_LOG"
    rm -f "$_PULL_LOG"
    fail "git reset failed (output above)"
fi
rm -f "$_PULL_LOG"
spin_stop "Up to date: $(git log -1 --format='%h %s')"

if [ "$_OLD_HEAD" != "$(git rev-parse HEAD)" ]; then
    git --no-pager diff --stat "$_OLD_HEAD" HEAD
    printf "\n"
    # update.sh just rewrote itself on disk (git reset --hard touches every
    # tracked file, this script included). Bash reads a running script
    # incrementally from disk by byte offset — continuing to execute the
    # rest of THIS process after the underlying file changed size/content
    # reads from a now-meaningless offset and corrupts execution partway
    # through, with no clean error (this has been silently breaking every
    # update that changes update.sh itself). Re-exec fresh from the new
    # file instead of limping along on stale buffered content.
    info "update.sh changed — restarting from the updated version..."
    exec bash "$SCRIPT_DIR/update.sh" "$@"
else
    dim "No changes — already up to date."
fi

# ── Backfill env vars ─────────────────────────────────────────────────────────
chmod 600 "$ENV_FILE"
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
export GIT_COMMIT="$(git rev-parse HEAD)"

info "Loading vendored images (if any)..."
load_vendored_images "$SCRIPT_DIR/takserver-dist"
ok "Vendored images loaded"

info "Building updated image..."
docker compose --env-file "$ENV_FILE" build \
    || fail "Build failed (see output above)."
ok "Image built"

info "Restarting containers..."
# up -d (no preceding down) only recreates containers whose image/config
# actually changed — a plain admin-panel update leaves takserver_config's
# messaging/CoT service running undisturbed instead of bouncing everything.
docker compose --env-file "$ENV_FILE" up -d --remove-orphans \
    || fail "Container restart failed (see output above)."
ok "Containers restarted"

# admin_proxy (nginx) resolves the "admin" hostname once and holds that IP
# for the life of its worker process. If only "admin" got recreated above,
# admin_proxy would keep proxying to the old container's now-dead IP —
# every request 502s until nginx itself restarts. Force that restart every
# time so it always has a fresh resolution, regardless of what else changed.
info "Restarting admin_proxy (picks up admin's current address)..."
docker compose --env-file "$ENV_FILE" restart admin_proxy \
    || fail "admin_proxy restart failed (see output above)."
ok "admin_proxy restarted"

# ── Self-test, with automatic self-heal on failure ────────────────────────────
# A quick functional check right after the normal build — see scripts/_selftest.sh.
# If it fails, that's a strong signal the build above silently reused stale
# cache instead of picking up the code change (this has happened in practice).
# Rather than leaving a broken deployment for a human to debug, automatically
# escalate to health.sh, which forces a clean --no-cache rebuild and retests.
# Only if health.sh ALSO can't fix it do we fail hard.
printf "\n"
if ! package_selftest; then
    warn "Self-test failed — escalating to health.sh for automatic recovery"
    printf "\n"
    bash "$SCRIPT_DIR/health.sh" || fail "Health check failed — see output above."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}  ${W}Update complete${NC}                              ${G}│${NC}\n"
printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
printf "\n"
printf "  ${DIM}Logs:${NC}  docker compose --env-file takserver.env logs -f\n"
printf "\n"
