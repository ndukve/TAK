#!/usr/bin/env bash
# Self-heal + self-test the running deployment against the currently checked
# out git commit. Safe to run standalone at any time (does not pull/fetch —
# that's update.sh's job), and is also invoked automatically by update.sh if
# its own quick self-test fails after a normal build.
#
# Self-heal: verifies each running image's baked-in git-commit label matches
#   HEAD. A mismatch means Docker's layer cache silently reused a stale layer
#   instead of picking up code changes — this has happened in practice: files
#   changed on disk, git pull succeeded, but the built image kept running old
#   code. When detected, forces a --no-cache rebuild + restart automatically.
#
# Self-test: see scripts/_selftest.sh — verifies the package builder actually
#   produces the right zip layout for each client type, not just that the
#   image was built from the right commit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"
# shellcheck source=scripts/_selftest.sh
. "$SCRIPT_DIR/scripts/_selftest.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"
[ -d "$SCRIPT_DIR/.git" ] || fail "Not a git repo — clone via git, not manual download"
cd "$SCRIPT_DIR"

banner "Health Check"

GIT_COMMIT="$(git rev-parse HEAD)"
_DC="docker compose --env-file $ENV_FILE"

_deployed_commit() {
    docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$1" 2>/dev/null
}

# ── Self-heal ─────────────────────────────────────────────────────────────────
info "Checking deployed images against ${GIT_COMMIT:0:7}..."
_ADMIN_IMG="$($_DC images -q admin 2>/dev/null)"
_STALE=()
[ "$(_deployed_commit takserver:local)" = "$GIT_COMMIT" ] || _STALE+=("takserver_initialization")
{ [ -n "$_ADMIN_IMG" ] && [ "$(_deployed_commit "$_ADMIN_IMG")" = "$GIT_COMMIT" ]; } || _STALE+=("admin")

if [ "${#_STALE[@]}" -gt 0 ]; then
    warn "Stale build cache detected (${_STALE[*]}) — forcing a clean rebuild"
    export GIT_COMMIT
    info "Rebuilding without cache (${_STALE[*]})..."
    $_DC build --no-cache "${_STALE[@]}" \
        || fail "Clean rebuild failed (see output above)."
    ok "Clean rebuild done"

    _ADMIN_IMG="$($_DC images -q admin 2>/dev/null)"
    for svc in "${_STALE[@]}"; do
        ref="takserver:local"; [ "$svc" = "admin" ] && ref="$_ADMIN_IMG"
        [ "$(_deployed_commit "$ref")" = "$GIT_COMMIT" ] || \
            fail "Rebuild still doesn't match ${GIT_COMMIT:0:7} for '${svc}' after --no-cache — this isn't a caching issue, check the Dockerfile/build context directly."
    done
    ok "Clean rebuild now matches ${GIT_COMMIT:0:7}"

    info "Restarting containers..."
    $_DC up -d --remove-orphans \
        || fail "Container restart failed (see output above)."
    ok "Containers restarted"
else
    ok "Deployed images already match ${GIT_COMMIT:0:7}"
fi

# ── Self-test ─────────────────────────────────────────────────────────────────
package_selftest || fail "Self-test failed even after self-heal — something deeper than a caching issue is wrong. Check make_pkg_zip.sh and templates/ directly."

# ── Service status ────────────────────────────────────────────────────────────
info "Container status:"
$_DC ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null || $_DC ps

printf "\n"
printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}  ${W}Health check passed${NC}                          ${G}│${NC}\n"
printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
printf "\n"
