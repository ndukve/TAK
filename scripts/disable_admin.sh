#!/usr/bin/env -S /bin/bash

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

# Revoke then re-add without admin flag
info "Revoking admin rights"
/opt/scripts/delete_user.sh
/opt/scripts/enable_user.sh
ok "Admin rights removed"
