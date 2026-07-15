#!/usr/bin/env -S /bin/bash
# shellcheck shell=bash

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

TR=/opt/tak
CONFIG=${TR}/data/CoreConfig.xml
TAK_USER_GROUP=${TAK_USER_GROUP:-TAK-USERS}

[ -n "$USER_CERT_NAME" ] || fail "USER_CERT_NAME not set"
[[ "$TAK_USER_GROUP" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "TAK_USER_GROUP must contain only letters, numbers, dots, hyphens, or underscores"

cd ${TR}
. ./setenv.sh

info "Authorizing ${USER_CERT_NAME} in ${TAK_USER_GROUP} (IN + OUT)"
TAKCL_CORECONFIG_PATH="${CONFIG}" java -jar /opt/tak/utils/UserManager.jar \
    certmod -g "${TAK_USER_GROUP}" "/opt/tak/data/certs/files/${USER_CERT_NAME}.pem"
ok "${USER_CERT_NAME} authorized in ${TAK_USER_GROUP} (IN + OUT)"
