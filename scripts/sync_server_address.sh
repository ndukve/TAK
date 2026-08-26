# shellcheck shell=bash
# Keep takserver.env's TAK_SERVER_ADDRESS in sync with this host's actual
# reachable address — client packages bake this value in at generation
# time (see make_pkg_zip.sh), so a stale entry here silently ships dead
# connection info to every ATAK/WinTAK/iTAK package until someone notices.
#
# Preference order matches install.sh's own networking step: NetBird (wt0)
# > Tailscale (tailscale0) > host's primary outbound-route IP. Only
# overwrites the config when the CURRENT value is a bare IPv4 address —
# a hostname (DDNS, reverse proxy, etc.) is assumed deliberate and left
# alone, since auto-detection has no way to know that's still correct.
#
# Sourced by Makefile's `up` target and update.sh — kept self-contained
# (no _spinner.sh dependency) since the Makefile invokes it standalone.

_IPV4_RE='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'

detect_server_address() {
    local nb_ip ts_ip lan_ip
    nb_ip=$(ip addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true
    ts_ip=$(ip addr show tailscale0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true
    if [ -n "$nb_ip" ]; then
        printf '%s' "$nb_ip"
    elif [ -n "$ts_ip" ]; then
        printf '%s' "$ts_ip"
    else
        lan_ip=$(ip route get 1.1.1.1 2>/dev/null \
            | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1)
        printf '%s' "$lan_ip"
    fi
}

sync_server_address() {
    local env_file="${1:-takserver.env}"
    [ -f "$env_file" ] || return 0

    local current detected
    current=$(grep '^TAK_SERVER_ADDRESS=' "$env_file" | cut -d= -f2-)
    [[ "$current" =~ $_IPV4_RE ]] || return 0

    detected="$(detect_server_address)"
    [ -n "$detected" ] || return 0

    if [ "$detected" != "$current" ]; then
        printf '  !  TAK_SERVER_ADDRESS changed (%s -> %s) — updating %s\n' "$current" "$detected" "$env_file"
        sed -i "s|^TAK_SERVER_ADDRESS=.*|TAK_SERVER_ADDRESS=${detected}|" "$env_file"
    fi
}
