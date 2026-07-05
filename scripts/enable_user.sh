#!/usr/bin/env -S /bin/bash
# shellcheck shell=bash

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

TR=/opt/tak
CONFIG=${TR}/data/CoreConfig.xml

[ -n "$USER_CERT_NAME" ] || fail "USER_CERT_NAME not set"

cd ${TR}
. ./setenv.sh

info "Authorizing ${USER_CERT_NAME} on server"
TAKCL_CORECONFIG_PATH="${CONFIG}" java -jar /opt/tak/utils/UserManager.jar \
    certmod "/opt/tak/data/certs/files/${USER_CERT_NAME}.pem"
ok "${USER_CERT_NAME} authorized"
