#!/usr/bin/env bash
# Keeps the server's data outside Docker. Sourced by install.sh and update.sh.
#
# Everything that must survive a reinstall lives on the host under TAK_DATA_DIR (default /srv/tak-data), bind-mounted into the
# containers: the CA, certificates and packages (takserver_data), the plugins and their config, and the PostgreSQL data.
# Images, containers and Docker's own state can be deleted, rebuilt or lost without touching it.

TAK_DATA_DIR_DEFAULT="/srv/tak-data"
DATA_PARTS=(takserver_data tak_plugins tak_plugin_conf takdb_data)

# ensure_data_dir <env file>: record TAK_DATA_DIR in the env file and create the directories (root only).
ensure_data_dir() {
    local env_file="$1" dir
    if ! grep -q '^TAK_DATA_DIR=' "$env_file"; then
        printf 'TAK_DATA_DIR=%s\n' "$TAK_DATA_DIR_DEFAULT" >> "$env_file"
        ok "Added TAK_DATA_DIR=${TAK_DATA_DIR_DEFAULT}"
    fi
    dir="$(grep '^TAK_DATA_DIR=' "$env_file" | tail -1 | cut -d= -f2-)"
    case "$dir" in
        /?*) ;;
        *) fail "TAK_DATA_DIR must be an absolute path (got '${dir}')" ;;
    esac
    # A data directory inside Docker's own root would be lost with it, which is the case this exists to prevent.
    case "$dir" in
        /var/lib/docker|/var/lib/docker/*) fail "TAK_DATA_DIR must not be inside /var/lib/docker" ;;
    esac
    mkdir -p "$dir"
    chmod 755 "$dir"
    local part
    for part in "${DATA_PARTS[@]}"; do mkdir -p "$dir/$part"; done
    TAK_DATA_DIR="$dir"
    export TAK_DATA_DIR
}

# _dir_has_data <dir>: true if the directory holds anything. Read as root in a throwaway container, because the data is owned by
# the services' own uids (mode 700) and an unprivileged `ls` would report "empty" and invite a copy over live data.
_dir_has_data() {
    [ -n "$(docker run --rm -u 0 --network none -v "$1:/d:ro" --entrypoint sh nginx:alpine -c 'ls -A /d | head -n 1')" ]
}

# migrate_volumes_to_data_dir <env file>: once, copy the data of the old named Docker volumes of THIS Compose project into
# TAK_DATA_DIR. The old volumes are left in place (nothing is deleted); a part whose directory already holds data, or that was
# migrated before (marker file), is never overwritten. Run with the containers stopped.
migrate_volumes_to_data_dir() {
    local env_file="$1" project part volume dest marker
    project="$(docker compose --env-file "$env_file" config 2>/dev/null | awk '/^name:/ {print $2; exit}')"
    project="${project:-$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]')}"
    for part in "${DATA_PARTS[@]}"; do
        volume="${project}_${part}"
        dest="${TAK_DATA_DIR}/${part}"
        marker="${TAK_DATA_DIR}/.migrated-${part}"
        docker volume inspect "$volume" >/dev/null 2>&1 || continue
        [ ! -e "$marker" ] || continue
        if _dir_has_data "$dest"; then
            info "${part}: ${dest} already has data, the old volume ${volume} is left alone"
            touch "$marker"
            continue
        fi
        info "${part}: copying volume ${volume} to ${dest}"
        # Root, no network, the old volume read-only; nginx:alpine is one of the vendored images (busybox cp).
        docker run --rm -u 0 --network none -v "${volume}:/from:ro" -v "${dest}:/to" --entrypoint cp nginx:alpine -a /from/. /to/ \
            || fail "Copying ${volume} failed. Nothing was removed; fix the cause and run ./update.sh again."
        touch "$marker"
        ok "${part} moved to ${dest} (the old volume ${volume} is kept; remove it yourself once all is well)"
    done
}
