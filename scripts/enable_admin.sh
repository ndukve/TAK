#!/usr/bin/env -S /bin/bash

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

TR=/opt/tak
CONFIG=${TR}/data/CoreConfig.xml

cd ${TR}
. ./setenv.sh

info "Waiting for TAK server"
WAITFORIT_TIMEOUT=2 /usr/bin/wait-for-it.sh localhost:8089 -- true

info "Granting admin rights to ${ADMIN_CERT_NAME}"
TAKCL_CORECONFIG_PATH="${CONFIG}" java -jar /opt/tak/utils/UserManager.jar \
    certmod -A "/opt/tak/data/certs/files/${ADMIN_CERT_NAME}.pem"
ok "${ADMIN_CERT_NAME} has admin rights"
