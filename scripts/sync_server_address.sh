# shellcheck shell=bash
# Keep takserver.env's TAK_SERVER_ADDRESS (and, when a VPN is active,
# TAK_SERVER_ADDRESS_LAN) in sync with this host's actual reachable
# addresses — client packages bake these in at generation time (see
# make_pkg_zip.sh / templates/*/blueteam.pref.tpl, which emit a second
# cot_streams entry when TAK_SERVER_ADDRESS_LAN is set), so a stale entry
# here silently ships dead connection info to every ATAK/WinTAK/iTAK
# package until someone notices.
#
# Preference order for the primary address matches install.sh's own
# networking step: NetBird (wt0) > Tailscale (tailscale0) > host's
# primary outbound-route IP. NetBird resolves to its own stable per-peer
# FQDN (e.g. tak-133-110.efdi.ltu, via NetBird's internal DNS — see
# `netbird status`) rather than the raw peer IP, which is the more
# durable identifier of the two: the IP can be reassigned on
# re-enrollment, the FQDN tracks the peer/hostname itself. Falls back to
# the raw wt0 IP if the FQDN can't be read for any reason.
#
# When a VPN is active, the LAN IP is ALSO detected and synced into
# TAK_SERVER_ADDRESS_LAN — devices on the same local network as the
# server (no VPN needed, e.g. a WinTAK VM alongside it) get a second,
# more direct connection option in the package. When no VPN is active,
# TAK_SERVER_ADDRESS already IS the LAN IP, so a separate LAN entry
# would be redundant — TAK_SERVER_ADDRESS_LAN is cleared in that case.
#
# Overwrites a config value when it's currently unset or a bare IPv4
# address (always safe — that's the literal stale-address bug this
# exists to fix), or when it's a hostname sharing the same domain suffix
# as a freshly-detected NetBird FQDN (the peer's own hostname changed —
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

_vpn_ip() {
    ip addr show "$1" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1
}

# Host's primary outbound-route IP — the real LAN/WAN address, independent
# of any VPN interface.
detect_lan_ip() {
    ip route get 1.1.1.1 2>/dev/null \
        | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1
}

detect_server_address() {
    local nb_ip nb_fqdn ts_ip
    nb_ip=$(_vpn_ip wt0) || true
    ts_ip=$(_vpn_ip tailscale0) || true
    if [ -n "$nb_ip" ]; then
        nb_fqdn=$(command -v netbird >/dev/null 2>&1 \
            && netbird status 2>/dev/null | awk -F': ' '/^FQDN:/ {print $2}') || true
        printf '%s' "${nb_fqdn:-$nb_ip}"
    elif [ -n "$ts_ip" ]; then
        printf '%s' "$ts_ip"
    else
        detect_lan_ip
    fi
}

# Whether a VPN interface (NetBird or Tailscale) currently has an address —
# i.e. whether detect_server_address() above is returning a VPN address
# rather than the LAN IP directly.
_vpn_active() {
    [ -n "$(_vpn_ip wt0)" ] || [ -n "$(_vpn_ip tailscale0)" ]
}

_set_env_var() {
    local env_file="$1" key="$2" value="$3"
    if grep -q "^${key}=" "$env_file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$env_file"
    fi
}

sync_server_address() {
    local env_file="${1:-takserver.env}"
    [ -f "$env_file" ] || return 0

    local current detected
    current=$(grep '^TAK_SERVER_ADDRESS=' "$env_file" | cut -d= -f2-)
    detected="$(detect_server_address)"
    if [ -n "$detected" ] && [ "$detected" != "$current" ]; then
        if [ -z "$current" ] || _is_ipv4 "$current"; then
            : # unset, or the literal stale-IP case — always safe to set
        elif ! _is_ipv4 "$detected" && [ "$(_domain_suffix "$current")" = "$(_domain_suffix "$detected")" ]; then
            : # same NetBird DNS domain, just a different peer hostname — still safe
        else
            detected="" # looks like a deliberately-set custom hostname — leave it alone
        fi
        if [ -n "$detected" ]; then
            printf '  !  TAK_SERVER_ADDRESS changed (%s -> %s) — updating %s\n' "${current:-<unset>}" "$detected" "$env_file"
            _set_env_var "$env_file" TAK_SERVER_ADDRESS "$detected"
        fi
    fi

    local current_lan lan_detected
    current_lan=$(grep '^TAK_SERVER_ADDRESS_LAN=' "$env_file" | cut -d= -f2-)
    if _vpn_active; then
        lan_detected="$(detect_lan_ip)"
        if [ -n "$lan_detected" ] && [ "$lan_detected" != "$current_lan" ] \
            && { [ -z "$current_lan" ] || _is_ipv4 "$current_lan"; }; then
            printf '  !  TAK_SERVER_ADDRESS_LAN changed (%s -> %s) — updating %s\n' "${current_lan:-<unset>}" "$lan_detected" "$env_file"
            _set_env_var "$env_file" TAK_SERVER_ADDRESS_LAN "$lan_detected"
        fi
    elif [ -n "$current_lan" ] && _is_ipv4 "$current_lan"; then
        # No VPN active anymore — TAK_SERVER_ADDRESS already covers the LAN
        # case directly, so a separate (now stale) LAN entry would just
        # produce a redundant or dead second cot_streams entry in packages.
        printf '  !  TAK_SERVER_ADDRESS_LAN cleared (no VPN active) — updating %s\n' "$env_file"
        _set_env_var "$env_file" TAK_SERVER_ADDRESS_LAN ""
    fi
}
