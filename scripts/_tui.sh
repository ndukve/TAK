# shellcheck shell=bash
# Shared whiptail TUI helpers — source this from any interactive script.
# Requires: set -euo pipefail already active in the caller.

# shellcheck disable=SC2034  # colors used by scripts that source this file, not within it
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m'
W='\033[1;37m' DIM='\033[2m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*"; exit 1; }
warn() { printf "${Y}  !${NC}  %s\n" "$*"; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }
dim()  { printf "${DIM}     %s${NC}\n" "$*"; }

if ! command -v whiptail &>/dev/null; then
    echo "Installing whiptail (installer UI)..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq whiptail
    elif command -v dnf &>/dev/null; then
        dnf install -y -q newt
    else
        echo "whiptail is required and no supported package manager (apt/dnf) was found." >&2
        exit 1
    fi
fi

# Dark-grey installer palette
export NEWT_COLORS='
root=white,gray
window=white,gray
border=white,gray
title=yellow,gray
button=black,cyan
actbutton=white,red
checkbox=black,cyan
actcheckbox=white,cyan
entry=black,cyan
label=white,gray
listbox=black,cyan
actlistbox=white,cyan
textbox=black,cyan
acttextbox=white,cyan
helpline=white,gray
roottext=white,gray
emptyscale=,cyan
fullscale=,gray
disentry=white,gray
disabledbutton=black,gray
'

WT_BACKTITLE="${WT_BACKTITLE:-TAK Server}"

wt_msg() { whiptail --backtitle "$WT_BACKTITLE" --title "$1" --msgbox "$2" "${3:-12}" "${4:-72}"; }

wt_yesno() { whiptail --backtitle "$WT_BACKTITLE" --title "$1" --yesno "$2" "${3:-10}" "${4:-72}"; }

wt_input() {
    # wt_input VAR "Title" "Prompt" ["default"]
    local _var="$1" _title="$2" _prompt="$3" _default="${4:-}" _result
    _result=$(whiptail --backtitle "$WT_BACKTITLE" --title "$_title" \
        --inputbox "$_prompt" 10 72 "$_default" 3>&1 1>&2 2>&3) || fail "Cancelled."
    [ -n "$_result" ] || _result="$_default"
    printf -v "$_var" '%s' "$_result"
}

wt_input_required() {
    local _var="$1" _title="$2" _prompt="$3" _result
    while true; do
        _result=$(whiptail --backtitle "$WT_BACKTITLE" --title "$_title" \
            --inputbox "$_prompt" 10 72 3>&1 1>&2 2>&3) || fail "Cancelled."
        [ -n "$_result" ] && break
        wt_msg "Required" "This field cannot be empty." 8 50
    done
    printf -v "$_var" '%s' "$_result"
}

wt_password() {
    local _var="$1" _title="$2" _prompt="$3" _result
    while true; do
        _result=$(whiptail --backtitle "$WT_BACKTITLE" --title "$_title" \
            --passwordbox "$_prompt" 10 72 3>&1 1>&2 2>&3) || fail "Cancelled."
        [ -n "$_result" ] && break
        wt_msg "Required" "This field cannot be empty." 8 50
    done
    printf -v "$_var" '%s' "$_result"
}

wt_menu() {
    # wt_menu VAR "Title" "Prompt" TAG1 ITEM1 TAG2 ITEM2 ...
    local _var="$1" _title="$2" _prompt="$3"; shift 3
    local _n=$(( $# / 2 ))
    local _result
    _result=$(whiptail --backtitle "$WT_BACKTITLE" --title "$_title" \
        --menu "$_prompt" $(( 9 + _n )) 72 "$_n" "$@" 3>&1 1>&2 2>&3) || fail "Cancelled."
    printf -v "$_var" '%s' "$_result"
}

# Ask how long the server keeps CoT history. TAK stores every CoT in the database (track history,
# replay, data sync); a busy server writes gigabytes a day, so the retention window sets the disk it needs.
# Sets TAK_RETENTION_COT_DAYS (days, or "null" for forever) and TAK_RETENTION_CRON (purge schedule).
# Both can be preset in the environment to skip the question.
ask_cot_retention() {
    local _title="$1"
    if [ -z "${TAK_RETENTION_COT_DAYS:-}" ]; then
        wt_menu TAK_RETENTION_COT_DAYS "$_title" \
"How long should the server keep CoT history?\nOlder data is deleted nightly at 03:00." \
            1 "24 hours (recommended)" 3 "3 days" 7 "7 days" 30 "30 days" null "Keep everything (disk grows without limit)"
    fi
    [[ "$TAK_RETENTION_COT_DAYS" =~ ^([1-9][0-9]*|null)$ ]] \
        || fail "TAK_RETENTION_COT_DAYS must be a number of days or 'null' (got '$TAK_RETENTION_COT_DAYS')."
    if [ "$TAK_RETENTION_COT_DAYS" = "null" ]; then
        TAK_RETENTION_CRON="-"
    else
        TAK_RETENTION_CRON="${TAK_RETENTION_CRON:-0 0 3 * * *}"
    fi
}

# The server needs about 128 GB: the database, the container images and their build cache.
# Warn, and let the admin continue, when the root filesystem is clearly smaller.
check_install_disk() {
    local total_gb
    total_gb=$(df -BG --output=size / 2>/dev/null | tail -1 | tr -dc '0-9')
    [ -n "$total_gb" ] && [ "$total_gb" -lt 120 ] || return 0
    wt_yesno "Disk space" "This server has about ${total_gb} GB of disk. TAK Server needs 128 GB: the CoT database, the container images and their build cache.\n\nContinue anyway?" 12 72 \
        || { clear; echo "Aborted."; exit 0; }
}

# Run a command with a live gauge; on failure, show the full log in a
# scrollable box AND dump it to the terminal so nothing is ever hidden.
run_with_gauge() {
    local title="$1" msg="$2"; shift 2
    [ "${1:-}" = "--" ] && shift
    local logfile; logfile=$(mktemp)
    "$@" > "$logfile" 2>&1 &
    local cmd_pid=$!
    ( local pct=0
      while kill -0 "$cmd_pid" 2>/dev/null; do
          pct=$(( pct < 92 ? pct + 2 : pct ))
          echo "$pct"
          sleep 0.3
      done
      echo 100
    ) | whiptail --backtitle "$WT_BACKTITLE" --title "$title" --gauge "$msg" 8 72 0 || true
    wait "$cmd_pid"; local rc=$?
    if [ "$rc" -ne 0 ]; then
        whiptail --backtitle "$WT_BACKTITLE" --title "$title — FAILED" --scrolltext --textbox "$logfile" 22 78
        printf "\n${R}  ✗  %s failed — full output:${NC}\n\n" "$title"
        cat "$logfile"
        rm -f "$logfile"
        return 1
    fi
    rm -f "$logfile"
    return 0
}
