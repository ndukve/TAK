#!/usr/bin/env bash
# Restore from a backup made by ./backup.sh. DESTRUCTIVE — overwrites the
# current admin database, TAK CoT database, certs/packages, plugins, and
# maps. Run from the repo directory:
#   ./restore.sh <backup-dir>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"
[ -n "${1:-}" ] || fail "Usage: ./restore.sh <backup-dir>"
BACKUP_DIR="$1"
[ -d "$BACKUP_DIR" ] || fail "Backup directory not found: $BACKUP_DIR"
[ -f "$BACKUP_DIR/admin_db.sql" ] || fail "Not a valid backup — admin_db.sql missing in $BACKUP_DIR"

cd "$SCRIPT_DIR"
banner "Restore"

warn "This overwrites the CURRENT admin database, TAK certs/packages, plugins, and maps with the backup at:"
dim "$BACKUP_DIR"
printf "\n"
read -rp "Type 'restore' to confirm: " CONFIRM
[ "$CONFIRM" = "restore" ] || fail "Aborted — confirmation text did not match."

PGUSER=$(grep '^POSTGRES_USER=' "$ENV_FILE" | cut -d= -f2)
PGUSER="${PGUSER:-martiuser}"

info "Stopping admin (avoid writes during restore)..."
docker compose --env-file "$ENV_FILE" stop admin admin_proxy || true

run_spin "Restoring admin database" "admin database restored" bash -c \
    "docker compose --env-file '$ENV_FILE' exec -T takdb psql -U '$PGUSER' -c 'DROP DATABASE IF EXISTS admin;' \
    && docker compose --env-file '$ENV_FILE' exec -T takdb psql -U '$PGUSER' -c 'CREATE DATABASE admin;' \
    && docker compose --env-file '$ENV_FILE' exec -T takdb psql -U '$PGUSER' admin < '$BACKUP_DIR/admin_db.sql'" \
    || fail "admin database restore failed (see output above)."

if [ -f "$BACKUP_DIR/cot_db.sql" ]; then
    run_spin "Restoring cot database" "cot database restored" bash -c \
        "docker compose --env-file '$ENV_FILE' exec -T takdb psql -U '$PGUSER' -c 'DROP DATABASE IF EXISTS cot;' \
        && docker compose --env-file '$ENV_FILE' exec -T takdb psql -U '$PGUSER' -c 'CREATE DATABASE cot;' \
        && docker compose --env-file '$ENV_FILE' exec -T takdb psql -U '$PGUSER' cot < '$BACKUP_DIR/cot_db.sql'" \
        || fail "cot database restore failed (see output above)."
else
    warn "No cot_db.sql in backup — skipped"
fi

if [ -f "$BACKUP_DIR/takserver_data.tar.gz" ]; then
    run_spin "Restoring certs and packages" "certs/packages restored" bash -c \
        "cat '$BACKUP_DIR/takserver_data.tar.gz' | docker compose --env-file '$ENV_FILE' exec -T admin bash -c 'rm -rf /opt/tak/data/* && tar xzf - -C /opt/tak/data'" \
        || fail "takserver_data restore failed (see output above)."
else
    warn "No takserver_data.tar.gz in backup — skipped"
fi

if [ -f "$BACKUP_DIR/tak_plugins.tar.gz" ]; then
    run_spin "Restoring plugins" "plugins restored" bash -c \
        "cat '$BACKUP_DIR/tak_plugins.tar.gz' | docker compose --env-file '$ENV_FILE' exec -T admin bash -c 'rm -rf /opt/tak/plugins/* && tar xzf - -C /opt/tak/plugins'" \
        || fail "plugins restore failed (see output above)."
else
    warn "No tak_plugins.tar.gz in backup — skipped"
fi

if [ -f "$BACKUP_DIR/tak-maps.tar.gz" ]; then
    info "Restoring maps..."
    rm -rf "$SCRIPT_DIR/packages/tak-maps"
    tar xzf "$BACKUP_DIR/tak-maps.tar.gz" -C "$SCRIPT_DIR/packages"
    ok "Maps restored"
else
    warn "No tak-maps.tar.gz in backup — skipped"
fi

info "Restarting containers..."
docker compose --env-file "$ENV_FILE" up -d --remove-orphans || fail "Container restart failed (see output above)."
ok "Containers restarted"

printf "\n"
printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
printf "  ${G}│${NC}  ${W}Restore complete${NC}                             ${G}│${NC}\n"
printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
printf "\n"
