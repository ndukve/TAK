#!/usr/bin/env bash
# Shared interactive-prompt helpers for TAK's post-install operational
# scripts (health.sh, etc.) — plain `read`-based, matching the convention
# already used by admin_fallback.sh and users.sh. install.sh's own first-time
# setup wizard uses whiptail (scripts/_tui.sh) instead; this file is for
# everything that runs after that, at a plain terminal.

ask() {  # ask <var> <question> [default]  — empty answer re-prompts if no default
    local _var="$1" _q="$2" _default="${3:-}" _ans
    if [ -n "$_default" ]; then
        read -rp "$(echo -e "  ${BOLD}${_q}${NC} [${_default}]: ")" _ans
        printf -v "$_var" '%s' "${_ans:-$_default}"
    else
        while true; do
            read -rp "$(echo -e "  ${BOLD}${_q}${NC}: ")" _ans
            [ -n "$_ans" ] && break
            echo "    (required)"
        done
        printf -v "$_var" '%s' "$_ans"
    fi
}

ask_opt() {  # ask_opt <var> <question> [default]  — empty answer allowed
    local _var="$1" _q="$2" _default="${3:-}" _ans
    if [ -n "$_default" ]; then
        read -rp "$(echo -e "  ${BOLD}${_q}${NC} [${_default}]: ")" _ans
        printf -v "$_var" '%s' "${_ans:-$_default}"
    else
        read -rp "$(echo -e "  ${BOLD}${_q}${NC} (leave blank to skip): ")" _ans
        printf -v "$_var" '%s' "${_ans:-}"
    fi
}

ask_secret() {  # ask_secret <var> <question>  — input hidden, no default
    local _var="$1" _q="$2" _ans
    read -rsp "$(echo -e "  ${BOLD}${_q}${NC}: ")" _ans
    echo
    printf -v "$_var" '%s' "$_ans"
}

ask_yes_no() {  # ask_yes_no <var> <question> [default: y|n, default n]  — sets <var> to 0 or 1
    local _var="$1" _q="$2" _default="${3:-n}" _ans _prompt="y/N"
    [ "$_default" = "y" ] && _prompt="Y/n"
    read -rp "$(echo -e "  ${BOLD}${_q}${NC} [${_prompt}]: ")" _ans
    case "${_ans:-$_default}" in
        [Yy]*) printf -v "$_var" '1' ;;
        *)     printf -v "$_var" '0' ;;
    esac
}

env_value() {
    local key="$1"
    [ -f "$ENV_FILE" ] || return 0
    sed -n "s/^${key}=//p" "$ENV_FILE" | head -1
}
