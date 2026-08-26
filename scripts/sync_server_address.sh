# shellcheck shell=bash
# Keep takserver.env's TAK_SERVER_ADDRESS in sync with this host's actual
# reachable address — client packages bake this value in at generation
# time (see make_pkg_zip.sh), so a stale entry here silently ships dead
# connection info to every ATAK/WinTAK/iTAK package until someone notices.
#
# Preference order matches install.sh's own networking step: NetBird (wt0)
# > Tailscale (tailscale0) > host's primary outbound-route IP. NetBird
# resolves to its own stable per-peer FQDN (e.g. tak-133-110.efdi.ltu,
# via NetBird's internal DNS — see `netbird status`) rather than the raw
# peer IP, which is the more durable identifier of the two: the IP can be
# reassigned on re-enrollment, the FQDN tracks the peer/hostname itself.
# Falls back to the raw wt0 IP if the FQDN can't be read for any reason.
#
# Overwrites the config when the CURRENT value is a bare IPv4 address
# (always safe — that's the literal stale-address bug this exists to
# fix), or when it's a hostname sharing the same domain suffix as a
# freshly-detected NetBird FQDN (the peer's own hostname changed —
# renamed machine, re-enrollment — but it's still NetBird's DNS domain,
# so still safe to follow). A hostname on a DIFFERENT domain (DDNS,
# reverse proxy, anything not NetBird-issued) is assumed deliberate and
# left alone, since auto-detection has no way to know that's still
# correct.
#
# Sourced by Makefile's `up` target and update.sh — kept self-contained
# (no _spinner.sh dependency) since the Makefile invokes it standalone.

_IPV4_RE='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'

_is_ipv4() { [[ "$1" =~ $_IPV4_RE ]]; }
_domain_suffix() { printf '%s' "${1#*.}"; }

detect_server_address() {
    local nb_ip nb_fqdn ts_ip lan_ip
    nb_ip=$(ip addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true
    ts_ip=$(ip addr show tailscale0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1) || true
    if [ -n "$nb_ip" ]; then
        nb_fqdn=$(command -v netbird >/dev/null 2>&1 \
            && netbird status 2>/dev/null | awk -F': ' '/^FQDN:/ {print $2}') || true
        printf '%s' "${nb_fqdn:-$nb_ip}"
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
    detected="$(detect_server_address)"
    [ -n "$detected" ] || return 0
    [ "$detected" = "$current" ] && return 0

    if [ -z "$current" ] || _is_ipv4 "$current"; then
        : # unset, or the literal stale-IP case — always safe to set
    elif ! _is_ipv4 "$detected" && [ "$(_domain_suffix "$current")" = "$(_domain_suffix "$detected")" ]; then
        : # same NetBird DNS domain, just a different peer hostname — still safe
    else
        return 0 # looks like a deliberately-set custom hostname — leave it alone
    fi

    printf '  !  TAK_SERVER_ADDRESS changed (%s -> %s) — updating %s\n' "${current:-<unset>}" "$detected" "$env_file"
    sed -i "s|^TAK_SERVER_ADDRESS=.*|TAK_SERVER_ADDRESS=${detected}|" "$env_file"
}
