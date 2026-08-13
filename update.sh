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
# shellcheck source=scripts/scrub_admin_secret.sh
. "$SCRIPT_DIR/scripts/scrub_admin_secret.sh"

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
if ! git merge --ff-only "origin/$BRANCH" >> "$_PULL_LOG" 2>&1; then
    spin_stop ""
    cat "$_PULL_LOG"
    rm -f "$_PULL_LOG"
    fail "fast-forward update failed; preserve or move local changes, then retry (output above)"
fi
rm -f "$_PULL_LOG"
spin_stop "Up to date: $(git log -1 --format='%h %s')"

if [ "$_OLD_HEAD" != "$(git rev-parse HEAD)" ]; then
    git --no-pager diff --stat "$_OLD_HEAD" HEAD
    printf "\n"
    # update.sh may just have rewritten itself on disk. Bash reads a running script
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
DOCKER_SOCKET_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)
if [ -z "$DOCKER_SOCKET_GID" ]; then
    DOCKER_SOCKET_GID=$(getent group docker 2>/dev/null | cut -d: -f3 || true)
fi
DOCKER_SOCKET_GID=${DOCKER_SOCKET_GID:-0}
if grep -q '^DOCKER_SOCKET_GID=' "$ENV_FILE"; then
    sed -i "s/^DOCKER_SOCKET_GID=.*/DOCKER_SOCKET_GID=${DOCKER_SOCKET_GID}/" "$ENV_FILE"
else
    printf 'DOCKER_SOCKET_GID=%s\n' "$DOCKER_SOCKET_GID" >> "$ENV_FILE"
    ok "Added DOCKER_SOCKET_GID"
fi

# Building TAK temporarily needs room for its distribution, expanded WAR, base
# layers, and the previous image (which must remain available until replacement
# containers start). Fail before a long BuildKit run instead of dying halfway
# through extraction with an opaque unzip write error.
MIN_DOCKER_FREE_MB=${TAK_UPDATE_MIN_FREE_MB:-8192}
[[ "$MIN_DOCKER_FREE_MB" =~ ^[0-9]+$ ]] \
    || fail "TAK_UPDATE_MIN_FREE_MB must be a non-negative integer"
DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)
DOCKER_ROOT=${DOCKER_ROOT:-/var/lib/docker}
[ -d "$DOCKER_ROOT" ] || DOCKER_ROOT=/
DOCKER_FREE_MB=$(df -Pm "$DOCKER_ROOT" | awk 'NR == 2 {print $4}')
if [ -z "$DOCKER_FREE_MB" ] || ! [[ "$DOCKER_FREE_MB" =~ ^[0-9]+$ ]]; then
    fail "Could not determine free space for Docker storage at $DOCKER_ROOT"
fi
if (( DOCKER_FREE_MB < MIN_DOCKER_FREE_MB )); then
    docker system df 2>/dev/null || true
    warn "Reclaim unused build cache: docker builder prune -af"
    warn "Reclaim images unused by containers: docker image prune -af"
    fail "Only ${DOCKER_FREE_MB} MiB free on Docker storage ($DOCKER_ROOT); ${MIN_DOCKER_FREE_MB} MiB required. Free space deliberately, then retry. Set TAK_UPDATE_MIN_FREE_MB only to override this preflight intentionally."
fi
ok "Docker storage preflight: ${DOCKER_FREE_MB} MiB free"

# ── Admin DB ──────────────────────────────────────────────────────────────────
info "Ensuring admin database exists..."
PGUSER=$(grep '^POSTGRES_USER=' "$ENV_FILE" | cut -d= -f2)
PGUSER="${PGUSER:-martiuser}"
docker compose exec -T takdb psql -U "$PGUSER" \
    -c "CREATE DATABASE admin;" 2>/dev/null \
    && ok "admin database created" \
    || ok "admin database already exists"

# ── Rebuild ───────────────────────────────────────────────────────────────────
GIT_COMMIT="$(git rev-parse HEAD)"
export GIT_COMMIT

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
    || { dump_service_logs "$ENV_FILE"; fail "Container restart failed (see output above)."; }
ok "Containers restarted"

# The EFDI bridge is an always-on TAK integration. Reapply its shared routing
# group after every upgrade so older packages and restored certificates retain
# IN + OUT access even if their server-side assignment was lost.
info "Ensuring efdi-bridge has full TAK routing access..."
EFDI_BRIDGE_CERTS=$(docker compose --env-file "$ENV_FILE" exec -T takserver_config bash -c '
    for name in efdi-bridge efdi-bridge-ATAK efdi-bridge-WinTAK efdi-bridge-iTAK efdi-bridge-Service; do
        [ -f "/opt/tak/data/certs/files/${name}.pem" ] && printf "%s\n" "$name"
    done
    true
')
if [ -n "$EFDI_BRIDGE_CERTS" ]; then
    while IFS= read -r cert_name; do
        docker compose --env-file "$ENV_FILE" exec -T \
            -e USER_CERT_NAME="$cert_name" \
            takserver_config bash /opt/scripts/enable_user.sh \
            || fail "Could not restore full TAK routing access for $cert_name"
    done <<< "$EFDI_BRIDGE_CERTS"
    ok "efdi-bridge has full TAK routing access"
else
    dim "No efdi-bridge certificate found yet"
fi

scrub_admin_bootstrap_secret "$ENV_FILE" \
    || fail "Admin bootstrap credential could not be removed safely."

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
