#!/usr/bin/env bash
# Remove the one-time admin bootstrap password after the API has successfully
# completed startup and created the first account. Recreate the admin container
# so the plaintext is removed from both takserver.env and container metadata.

scrub_admin_bootstrap_secret() {
    local env_file="$1"
    local ready=0

    grep -q '^ADMIN_FIRST_PASS=.' "$env_file" || return 0

    for _ in $(seq 1 180); do
        if docker compose --env-file "$env_file" exec -T admin \
            python -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8889/auth/oidc/config", timeout=2)' \
            >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 2
    done

    if [ "$ready" -ne 1 ]; then
        echo "Admin API did not become ready; refusing to erase the bootstrap password." >&2
        return 1
    fi

    sed -i 's/^ADMIN_FIRST_PASS=.*/ADMIN_FIRST_PASS=/' "$env_file"
    chmod 600 "$env_file"
    docker compose --env-file "$env_file" up -d --no-deps --force-recreate admin >/dev/null
    docker compose --env-file "$env_file" restart admin_proxy >/dev/null
}
