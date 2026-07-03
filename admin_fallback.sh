#!/usr/bin/env bash
# Interactive break-glass fallback for the admin web UI: browse and download
# packages/maps from the terminal when the web UI is unavailable. Requires
# SSH/shell access to the server itself, same trust boundary as get_package.sh.
# Read-only: no create/delete, no user management.
# Usage: ./admin_fallback.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
MAPS_DIR="$SCRIPT_DIR/packages/tak-maps"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

list_packages() {
    docker compose --env-file "$ENV_FILE" exec -T takserver_config \
        bash -c "ls /opt/tak/data/certs/files/clientpkgs/*.zip 2>/dev/null | xargs -n1 basename" \
        || warn "No packages found."
}

download_package() {
    read -rp "Package name (without .zip): " NAME || { echo; return; }
    [ -n "$NAME" ] || { warn "No name given."; return; }
    local DEST="./${NAME}.zip"
    if [ -f "$DEST" ]; then
        warn "$DEST already exists in the current directory — remove it first or run this from elsewhere."
        return
    fi
    docker compose --env-file "$ENV_FILE" exec -T takserver_config \
        bash -c 'cat "/opt/tak/data/certs/files/clientpkgs/$1.zip"' -- "$NAME" > "$DEST" \
        || { rm -f "$DEST"; warn "Package '$NAME' not found."; return; }
    ok "Saved to $DEST"
}

list_maps() {
    if [ ! -d "$MAPS_DIR" ]; then
        warn "No maps directory found."
        return
    fi
    local found=0 provider_dir provider f
    for provider_dir in "$MAPS_DIR"/*/; do
        [ -d "$provider_dir" ] || continue
        provider="$(basename "$provider_dir")"
        for f in "$provider_dir"*; do
            [ -f "$f" ] || continue
            found=1
            echo "$provider/$(basename "$f")"
        done
    done
    [ "$found" -eq 1 ] || warn "No maps found."
}

download_map() {
    read -rp "Provider: " PROVIDER || { echo; return; }
    read -rp "Filename: " FNAME || { echo; return; }
    [ -n "$PROVIDER" ] && [ -n "$FNAME" ] || { warn "Provider and filename are required."; return; }
    local RESOLVED_ROOT SRC
    RESOLVED_ROOT="$(realpath -m "$MAPS_DIR")"
    SRC="$(realpath -m "$MAPS_DIR/$PROVIDER/$FNAME")"
    case "$SRC" in
        "$RESOLVED_ROOT"/*) ;;
        *) warn "Invalid provider/filename."; return ;;
    esac
    [ -f "$SRC" ] || { warn "Map not found."; return; }
    local DEST="./${FNAME}"
    if [ -f "$DEST" ]; then
        warn "$DEST already exists in the current directory — remove it first or run this from elsewhere."
        return
    fi
    cp "$SRC" "$DEST"
    ok "Saved to $DEST"
}

banner "Admin Fallback CLI (packages + maps, read-only)"
while true; do
    echo ""
    echo "1) List packages"
    echo "2) Download package"
    echo "3) List maps"
    echo "4) Download map"
    echo "5) Exit"
    read -rp "> " CHOICE || { echo; exit 0; }
    case "$CHOICE" in
        1) list_packages ;;
        2) download_package ;;
        3) list_maps ;;
        4) download_map ;;
        5) exit 0 ;;
        *) warn "Invalid choice." ;;
    esac
done
