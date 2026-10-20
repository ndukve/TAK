#!/usr/bin/env bash
# Back up the admin panel database, TAK CoT database, certs/packages,
# plugins, maps, and config. Run from the repo directory:
#   ./backup.sh [output-dir]
# Defaults to backups/<timestamp>/ if no output dir is given.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"
cd "$SCRIPT_DIR"

OUT_DIR="${1:-backups/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"

banner "Backup"
info "Writing to ${OUT_DIR}/"

PGUSER=$(grep '^POSTGRES_USER=' "$ENV_FILE" | cut -d= -f2)
PGUSER="${PGUSER:-martiuser}"

run_spin "Dumping admin database" "admin database dumped" bash -c \
    'docker compose --env-file "$1" exec -T takdb pg_dump -U "$2" admin > "$3"' _ \
    "$ENV_FILE" "$PGUSER" "$OUT_DIR/admin_db.sql" \
    || fail "admin database dump failed (see output above)."

run_spin "Dumping cot database" "cot database dumped" bash -c \
    'docker compose --env-file "$1" exec -T takdb pg_dump -U "$2" cot > "$3"' _ \
    "$ENV_FILE" "$PGUSER" "$OUT_DIR/cot_db.sql" \
    || fail "cot database dump failed (see output above)."

# The data lives on the host under TAK_DATA_DIR. The CA key and client keys are mode 600 and owned by TAK's own uid, which the admin
# container's user cannot read (a tar through it silently drops them), so read them as root from a throwaway container
# (nginx:alpine is a vendored image, busybox tar).
DATA_DIR="$(grep '^TAK_DATA_DIR=' "$ENV_FILE" | tail -1 | cut -d= -f2-)"
DATA_DIR="${DATA_DIR:-/srv/tak-data}"
run_spin "Archiving certs and packages" "certs/packages archived" bash -c \
    'docker run --rm -u 0 --network none -v "$1":/d:ro --entrypoint tar nginx:alpine czf - -C /d . > "$2"' _ \
    "$DATA_DIR/takserver_data" "$OUT_DIR/takserver_data.tar.gz" \
    || fail "takserver_data archive failed (see output above)."

run_spin "Archiving plugins" "plugins archived" bash -c \
    'docker run --rm -u 0 --network none -v "$1":/d:ro --entrypoint tar nginx:alpine czf - -C /d . > "$2"' _ \
    "$DATA_DIR/tak_plugins" "$OUT_DIR/tak_plugins.tar.gz" \
    || fail "tak_plugins archive failed (see output above)."

info "Archiving maps..."
if [ -d "$SCRIPT_DIR/packages/tak-maps" ]; then
    tar czf "$OUT_DIR/tak-maps.tar.gz" -C "$SCRIPT_DIR/packages" tak-maps
    ok "Maps archived"
else
    warn "No maps directory found — skipped"
fi

cp "$ENV_FILE" "$OUT_DIR/takserver.env"
ok "Config copied"

chmod 600 "$OUT_DIR"/*.sql "$OUT_DIR/takserver.env" 2>/dev/null || true

printf "\n"
printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}  ${W}Backup complete${NC}                              ${G}│${NC}\n"
printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
printf "\n"
printf "  ${DIM}Location:${NC} %s\n" "$OUT_DIR"
printf "  ${DIM}Restore with:${NC} ./restore.sh %s\n" "$OUT_DIR"
printf "\n"
