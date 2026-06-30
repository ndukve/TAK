#!/usr/bin/env -S /bin/bash
# Build the client data package zip from an existing cert.
# Requires gen_client_cert.sh to have run first (reads <name>.certpass).

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

TR=/opt/tak
CR=${TR}/data/certs
ZIPTGT=${CR}/files/clientpkgs

mkdir -p ${ZIPTGT}

[ -n "$CLIENT_CERT_NAME" ]   || fail "CLIENT_CERT_NAME not set"
[ -n "$TAK_SERVER_ADDRESS" ] || fail "TAK_SERVER_ADDRESS not set"

PASSFILE="${CR}/files/${CLIENT_CERT_NAME}.certpass"
[ -f "$PASSFILE" ]                              || fail "No cert password file — run gen-device-cert first"
[ -f "${CR}/files/${CLIENT_CERT_NAME}.p12" ]   || fail "No cert found — run gen-device-cert first"
[ ! -f "${ZIPTGT}/${CLIENT_CERT_NAME}.zip" ]   || fail "${CLIENT_CERT_NAME} package already exists"

export CLIENT_CERT_PASSWORD=$(cat "$PASSFILE")

info "Building data package for ${CLIENT_CERT_NAME}"

tmp_dir=$(mktemp -d "/tmp/newclient.XXXXXXXX")
WORK_DIR="${tmp_dir}/${CLIENT_CERT_NAME}"
mkdir -p ${WORK_DIR}

cp -R /opt/templates/missionpkg/* ${WORK_DIR}/

cat ${WORK_DIR}/content/blueteam.pref.tpl | gomplate > ${WORK_DIR}/content/blueteam.pref
cat ${WORK_DIR}/MANIFEST/manifest.xml.tpl  | gomplate > ${WORK_DIR}/MANIFEST/manifest.xml
rm ${WORK_DIR}/content/blueteam.pref.tpl ${WORK_DIR}/MANIFEST/manifest.xml.tpl

cp ${CR}/files/${CLIENT_CERT_NAME}.p12 ${WORK_DIR}/content/
cp ${CR}/files/truststore-root.p12     ${WORK_DIR}/content/

cd ${WORK_DIR}
zip -r ${tmp_dir}/${CLIENT_CERT_NAME}.zip ./ >/dev/null

mv ${tmp_dir}/${CLIENT_CERT_NAME}.zip ${ZIPTGT}/
rm -rf ${tmp_dir}

ok "Package ready: ${ZIPTGT}/${CLIENT_CERT_NAME}.zip"
