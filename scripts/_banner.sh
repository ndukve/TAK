#!/usr/bin/env bash
# Shared banner helpers, sourced by the interactive scripts before their project banner.
# os_banner prints the host's OS facts in the layout of the RutOS login banner (rule, title, rule, fields, rule),
# so every EFDI machine says what it runs before the TAK / EFDI GATEWAY / EFDI EDGE splash.
# NATO flag blue is #004990 (RGB 0, 73, 144; Pantone 280 C).

os_banner() {
    # NATO flag blue #004990: exact on a truecolor terminal, the nearest 256-colour entry (24) on an xterm-256color one, standard blue on a plain console (the Proxmox/Linux console has no 24-bit colour and would show cyan)
    case "${COLORTERM:-}" in *truecolor*|*24bit*) _NB='\033[38;2;0;73;144m' ;; *) if [ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ] 2>/dev/null; then _NB='\033[38;5;24m'; else _NB='\033[0;34m'; fi ;; esac
    local rule="--------------------------------------------------------" nb="$_NB" nc='\033[0m'
    local os kernel arch host virt up
    os="$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-}")"
    os="${os:-$(uname -s)}"
    kernel="$(uname -r)"
    arch="$(uname -m)"
    host="$(hostname 2>/dev/null || echo unknown)"
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    if [[ -z "$virt" || "$virt" == none ]]; then
        if [[ -f /.dockerenv ]]; then virt=container; else virt=physical; fi
    fi
    up="$(uptime -p 2>/dev/null | sed 's/^up //')"
    echo -e "${nb}${rule}${nc}"
    printf '%b%*s%s%b\n' "$nb" $(( (${#rule} - ${#os}) / 2 )) '' "$os" "$nc"
    echo -e "${nb}${rule}${nc}"
    printf '   %-12s%s\n' "Device:" "$host"
    printf '   %-12s%s\n' "Kernel:" "$kernel"
    printf '   %-12s%s\n' "Arch:" "$arch"
    printf '   %-12s%s\n' "Platform:" "$virt"
    [[ -n "$up" ]] && printf '   %-12s%s\n' "Uptime:" "$up"
    echo -e "${nb}${rule}${nc}"
}
