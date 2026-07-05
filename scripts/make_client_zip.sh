#!/usr/bin/env -S /bin/bash
# shellcheck shell=bash
# Legacy: generate cert AND package in one step (make_pkg_zip.sh is preferred).

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

TR=/opt/tak
CR=${TR}/data/certs
ZIPTGT=${CR}/files/clientpkgs

mkdir -p ${ZIPTGT}

[ -n "$CLIENT_CERT_NAME" ] || fail "CLIENT_CERT_NAME not set"

if [ -f "${ZIPTGT}/${CLIENT_CERT_NAME}.zip" ] || [ -f "${CR}/files/${CLIENT_CERT_NAME}.key" ]; then
    fail "${CLIENT_CERT_NAME} already exists"
fi

CLIENT_CERT_PASSWORD=$(pwgen -cn1 20 1) # pragma: allowlist secret
export CLIENT_CERT_PASSWORD

info "Generating certificate for ${CLIENT_CERT_NAME}"
tmp_dir=$(mktemp -d "/tmp/newclient.XXXXXXXX")
WORK_DIR="${tmp_dir}/${CLIENT_CERT_NAME}"
mkdir -p ${WORK_DIR}

cp -R /opt/templates/missionpkg/* ${WORK_DIR}/

cat ${WORK_DIR}/content/blueteam.pref.tpl | gomplate > ${WORK_DIR}/content/blueteam.pref
cat ${WORK_DIR}/MANIFEST/manifest.xml.tpl  | gomplate > ${WORK_DIR}/MANIFEST/manifest.xml
rm ${WORK_DIR}/content/blueteam.pref.tpl ${WORK_DIR}/MANIFEST/manifest.xml.tpl

cd ${CR}
CAPASS=${CA_PASS} PASS="${CLIENT_CERT_PASSWORD}" bash makeCert.sh client "${CLIENT_CERT_NAME}" >/dev/null

cp ${CR}/files/${CLIENT_CERT_NAME}.p12 ${WORK_DIR}/content/
cp ${CR}/files/truststore-root.p12     ${WORK_DIR}/content/

cd ${WORK_DIR}
zip -r ${tmp_dir}/${CLIENT_CERT_NAME}.zip ./ >/dev/null

if [ -f "${ZIPTGT}/${CLIENT_CERT_NAME}.zip" ]; then
    rm -rf ${tmp_dir}
    fail "${CLIENT_CERT_NAME} was created concurrently"
fi

mv ${tmp_dir}/${CLIENT_CERT_NAME}.zip ${ZIPTGT}/
rm -rf ${tmp_dir}

ok "Package ready: ${ZIPTGT}/${CLIENT_CERT_NAME}.zip"
