#!/usr/bin/env -S /bin/bash
# shellcheck shell=bash
# Build the client data package zip from an existing cert.
# Requires gen_client_cert.sh to have run first (reads <name>.certpass).
#
# CLIENT_CERT_NAME must end in -ATAK, -WinTAK, -iTAK, or -Service — this
# selects the package layout. iTAK requires certs + the preference file at
# the zip root (no content/ + MANIFEST/ nesting), unlike ATAK/WinTAK's
# Mission Package format, which iTAK's importer does not reliably recognize.
# Service has no TAK client app to import a mission package into, so it gets
# a decrypted PEM bundle (cert.pem/key.pem/ca.pem) for generic mTLS use
# instead — same shape as generate_service_cert.sh's terminal-only output.

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

case "$CLIENT_CERT_NAME" in
    *-iTAK)          TEMPLATE_DIR=/opt/templates/missionpkg-itak ;;
    *-ATAK|*-WinTAK) TEMPLATE_DIR=/opt/templates/missionpkg ;;
    *-Service)       TEMPLATE_DIR="" ;;
    *) fail "CLIENT_CERT_NAME must end in -ATAK, -WinTAK, -iTAK, or -Service (got: ${CLIENT_CERT_NAME})" ;;
esac

PASSFILE="${CR}/files/${CLIENT_CERT_NAME}.certpass"
[ -f "$PASSFILE" ]                              || fail "No cert password file — run gen-device-cert first"
[ -f "${CR}/files/${CLIENT_CERT_NAME}.p12" ]   || fail "No cert found — run gen-device-cert first"
[ ! -f "${ZIPTGT}/${CLIENT_CERT_NAME}.zip" ]   || fail "${CLIENT_CERT_NAME} package already exists"

CLIENT_CERT_PASSWORD=$(cat "$PASSFILE")
export CLIENT_CERT_PASSWORD

info "Building data package for ${CLIENT_CERT_NAME} (${TEMPLATE_DIR:-PEM bundle})"

tmp_dir=$(mktemp -d "/tmp/newclient.XXXXXXXX")
WORK_DIR="${tmp_dir}/${CLIENT_CERT_NAME}"
mkdir -p ${WORK_DIR}

[ -z "$TEMPLATE_DIR" ] || cp -R ${TEMPLATE_DIR}/* ${WORK_DIR}/

case "$CLIENT_CERT_NAME" in
    *-iTAK)
        # Flat layout: cert files + preference file at zip root.
        cat ${WORK_DIR}/blueteam.pref.tpl         | gomplate > ${WORK_DIR}/blueteam.pref
        cat ${WORK_DIR}/MANIFEST/manifest.xml.tpl | gomplate > ${WORK_DIR}/MANIFEST/manifest.xml
        rm ${WORK_DIR}/blueteam.pref.tpl ${WORK_DIR}/MANIFEST/manifest.xml.tpl
        cp ${CR}/files/${CLIENT_CERT_NAME}.p12 ${WORK_DIR}/
        cp ${CR}/files/truststore-root.p12     ${WORK_DIR}/
        ;;
    *-Service)
        # No TAK client app to import a mission package into — export a
        # decrypted PEM bundle instead (cert + key + CA), for generic mTLS
        # clients (e.g. Python ssl) that can't unlock an encrypted PKCS#12 key.
        [ -f "${CR}/files/${CLIENT_CERT_NAME}.pem" ] || fail "No cert found — run gen-device-cert first"
        [ -f "${CR}/files/ca.pem" ]                  || fail "Server CA cert not found at ${CR}/files/ca.pem"
        cp ${CR}/files/${CLIENT_CERT_NAME}.pem ${WORK_DIR}/cert.pem
        cp ${CR}/files/ca.pem                  ${WORK_DIR}/ca.pem
        openssl pkey -in ${CR}/files/${CLIENT_CERT_NAME}.key -passin pass:"${CLIENT_CERT_PASSWORD}" \
            > ${WORK_DIR}/key.pem
        chmod 600 ${WORK_DIR}/key.pem
        ;;
    *)
        # Nested Mission Package layout (ATAK/WinTAK): content/ + MANIFEST/.
        cat ${WORK_DIR}/content/blueteam.pref.tpl | gomplate > ${WORK_DIR}/content/blueteam.pref
        cat ${WORK_DIR}/MANIFEST/manifest.xml.tpl  | gomplate > ${WORK_DIR}/MANIFEST/manifest.xml
        rm ${WORK_DIR}/content/blueteam.pref.tpl ${WORK_DIR}/MANIFEST/manifest.xml.tpl
        cp ${CR}/files/${CLIENT_CERT_NAME}.p12 ${WORK_DIR}/content/
        cp ${CR}/files/truststore-root.p12     ${WORK_DIR}/content/
        ;;
esac

cd ${WORK_DIR}
zip -r ${tmp_dir}/${CLIENT_CERT_NAME}.zip ./ >/dev/null

mv ${tmp_dir}/${CLIENT_CERT_NAME}.zip ${ZIPTGT}/
rm -rf ${tmp_dir}

ok "Package ready: ${ZIPTGT}/${CLIENT_CERT_NAME}.zip"
