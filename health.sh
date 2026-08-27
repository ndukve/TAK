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
# shellcheck source=scripts/refresh_vendor.sh
. "$SCRIPT_DIR/scripts/refresh_vendor.sh"
# shellcheck source=scripts/_ask.sh
. "$SCRIPT_DIR/scripts/_ask.sh"
# shellcheck source=scripts/reset_admin_password.sh
. "$SCRIPT_DIR/scripts/reset_admin_password.sh"

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

    info "Loading vendored images (if any)..."
    load_vendored_images "$SCRIPT_DIR/takserver-dist"
    ok "Vendored images loaded"

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

    # admin_proxy caches admin's resolved IP for the life of its worker —
    # if only admin got recreated above, admin_proxy would keep 502ing
    # against the old container's dead IP until it restarts itself.
    info "Restarting admin_proxy (picks up admin's current address)..."
    $_DC restart admin_proxy \
        || fail "admin_proxy restart failed (see output above)."
    ok "admin_proxy restarted"
else
    ok "Deployed images already match ${GIT_COMMIT:0:7}"
fi

# ── Self-test ─────────────────────────────────────────────────────────────────
# Not `set -e`-fatal via fail(): that used to exit this whole script right
# here on a failed self-test — before ever reaching the troubleshooting menu
# below. A broken deployment is exactly when that menu matters most.
_HEALTH_FAILED=0
if ! package_selftest; then
    warn "Self-test failed even after self-heal — something deeper than a caching issue is wrong. Check make_pkg_zip.sh and templates/ directly."
    _HEALTH_FAILED=1
fi

# ── Service status ────────────────────────────────────────────────────────────
info "Container status:"
$_DC ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null || $_DC ps

printf "\n"
if [ "$_HEALTH_FAILED" -eq 0 ]; then
    printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
    printf "  ${G}│${NC}  ${W}Health check passed${NC}                          ${G}│${NC}\n"
    printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
else
    printf "  ${R}┌────────────────────────────────────────────────┐${NC}\n"
    printf "  ${R}│${NC}  ${W}Health check found issues — see above${NC}          ${R}│${NC}\n"
    printf "  ${R}└────────────────────────────────────────────────┘${NC}\n"
fi
printf "\n"

# Interactive troubleshooting menu — only when actually run by hand at a real
# terminal. update.sh calls this script unattended as an automatic-recovery
# escalation (see its own TAK_NONINTERACTIVE=1 before invoking it); without
# both checks, that automated call would hang forever on `read`.
if [ -t 0 ] && [ -z "${TAK_NONINTERACTIVE:-}" ]; then
    section "Troubleshooting"
    echo "  [1] Reset the admin panel username/password"
    echo "  [2] Restart a service"
    echo "  [3] Check for missing/misconfigured env vars"
    echo "  [Q] Done"
    read -rp "  Action [1/2/3/Q]: " _TS_ACTION
    case "${_TS_ACTION:-Q}" in
        1)
            _TS_CURRENT_USER="$(env_value ADMIN_FIRST_USER)"
            ask _TS_USER "Admin username" "${_TS_CURRENT_USER:-admin}"
            while true; do
                ask_secret _TS_PASS "New password (minimum 12 characters)"
                [ "${#_TS_PASS}" -ge 12 ] && break
                warn "Minimum 12 characters required."
            done
            if reset_admin_password "$ENV_FILE" "$_TS_USER" "$_TS_PASS"; then
                ok "Admin credentials reset for '$_TS_USER'"
            else
                warn "Could not reset admin credentials — see output above"
            fi
            unset _TS_PASS
            ;;
        2)
            echo "  Services:"
            $_DC ps --format '    {{.Service}}'
            ask _TS_SERVICE "Service name to restart"
            if $_DC restart "$_TS_SERVICE"; then
                ok "Restarted $_TS_SERVICE"
            else
                warn "Could not restart '$_TS_SERVICE' — check the name matches exactly what's listed above"
            fi
            ;;
        3)
            info "Checking takserver.env for expected keys..."
            _TS_MISSING=0
            for key in ADMIN_SECRET_KEY ADMIN_FIRST_USER POSTGRES_PASSWORD DOCKER_SOCKET_GID TAK_SERVER_ADDRESS; do
                if ! grep -q "^${key}=." "$ENV_FILE"; then
                    warn "$key is missing or empty in takserver.env"
                    _TS_MISSING=1
                fi
            done
            [ "$_TS_MISSING" -eq 0 ] && ok "No known config gaps found"
            ;;
        *) ;;
    esac
fi

# Deferred from the self-test above so an automated caller (update.sh's
# TAK_NONINTERACTIVE=1 escalation) still sees a non-zero exit and its own
# `|| fail` still fires — only the hard, mid-script exit was removed.
exit "$_HEALTH_FAILED"
