#!/usr/bin/env -S /bin/bash
# Fully remove a user: revoke on the server AND delete cert/package files so
# the callsign becomes reusable. Revoking alone (UserManager certmod -g
# revoked) leaves the .key/.p12/.certpass/.zip files in place, which makes
# gen_client_cert.sh refuse to recreate the same name afterward.

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

TR=/opt/tak
CONFIG=${TR}/data/CoreConfig.xml
CR=${TR}/data/certs

[ -n "$USER_CERT_NAME" ] || fail "USER_CERT_NAME not set"

cd ${TR}
. ./setenv.sh

info "Revoking ${USER_CERT_NAME}"
TAKCL_CORECONFIG_PATH="${CONFIG}" java -jar /opt/tak/utils/UserManager.jar \
    certmod -g revoked "/opt/tak/data/certs/files/${USER_CERT_NAME}.pem" \
    && ok "${USER_CERT_NAME} revoked" \
    || info "Revoke skipped (cert not registered with UserManager, or already revoked)"

info "Removing certificate and package files"
rm -f ${CR}/files/${USER_CERT_NAME}.* ${CR}/files/clientpkgs/${USER_CERT_NAME}.zip
ok "${USER_CERT_NAME} files removed"
