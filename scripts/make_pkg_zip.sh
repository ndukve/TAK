#!/usr/bin/env -S /bin/bash
# Build the client data package zip from an existing cert.
# Requires gen_client_cert.sh to have run first (reads <name>.certpass).

set -e

TR=/opt/tak
CR=${TR}/data/certs
ZIPTGT=${CR}/files/clientpkgs

mkdir -p ${ZIPTGT}

[ -n "$CLIENT_CERT_NAME" ] || { echo "CLIENT_CERT_NAME not set"; exit 1; }
[ -n "$TAK_SERVER_ADDRESS" ] || { echo "TAK_SERVER_ADDRESS not set"; exit 1; }

PASSFILE="${CR}/files/${CLIENT_CERT_NAME}.certpass"
[ -f "$PASSFILE" ] || { echo "No cert password file — run gen-device-cert first"; exit 1; }
[ -f "${CR}/files/${CLIENT_CERT_NAME}.p12" ] || { echo "No cert found — run gen-device-cert first"; exit 1; }
[ ! -f "${ZIPTGT}/${CLIENT_CERT_NAME}.zip" ] || { echo "${CLIENT_CERT_NAME} package already exists"; exit 1; }

export CLIENT_CERT_PASSWORD=$(cat "$PASSFILE")

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
zip -r ${tmp_dir}/${CLIENT_CERT_NAME}.zip ./

mv ${tmp_dir}/${CLIENT_CERT_NAME}.zip ${ZIPTGT}/
rm -rf ${tmp_dir}

echo "Package ready: ${ZIPTGT}/${CLIENT_CERT_NAME}.zip"
