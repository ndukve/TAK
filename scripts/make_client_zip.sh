#!/usr/bin/env -S /bin/bash

set -e

TR=/opt/tak

CR=${TR}/data/certs

ZIPTGT=${CR}/files/clientpkgs

mkdir -p ${ZIPTGT}

if [ -z "$CLIENT_CERT_NAME" ]

then

echo "CLIENT_CERT_NAME not set"

exit 1

fi

if [ -f ${ZIPTGT}/${CLIENT_CERT_NAME}.zip ] || [ -f ${CR}/files/${CLIENT_CERT_NAME}.key ]

then

echo "${CLIENT_CERT_NAME} already exists !"

exit 1

fi

export CLIENT_CERT_PASSWORD=`pwgen -cn1 20 1` # pragma: allowlist secret

tmp_dir=$(mktemp -d "/tmp/newclient.XXXXXXXX")

WORK_DIR=$tmp_dir"/"$CLIENT_CERT_NAME

mkdir -p $WORK_DIR

cp -R /opt/templates/missionpkg/* $WORK_DIR/

cat ${WORK_DIR}/content/blueteam.pref.tpl | gomplate >${WORK_DIR}/content/blueteam.pref
rm ${WORK_DIR}/content/blueteam.pref.tpl ${WORK_DIR}/MANIFEST/manifest.xml.tpl

# Copy all map source XMLs from the maps submodule
MAPS_DIR=/opt/tak/maps
if [ -d "$MAPS_DIR" ]; then
    find "$MAPS_DIR" -name "*.xml" | while read xmlfile; do
        cp "$xmlfile" "${WORK_DIR}/content/"
    done
fi

# Generate manifest dynamically to include all content files
MAP_ENTRIES=""
for f in "${WORK_DIR}/content/"*.xml; do
    [ -f "$f" ] || continue
    MAP_ENTRIES="${MAP_ENTRIES}    <Content ignore=\"false\" zipEntry=\"content/$(basename $f)\"/>\n"
done

UID_VAL=$(echo "${TAK_SERVER_NAME:-takserver}-DEFAULT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
cat > "${WORK_DIR}/MANIFEST/manifest.xml" << MANIFEST
<MissionPackageManifest version="2">
<Configuration>
<Parameter name="uid" value="${UID_VAL}"/>
<Parameter name="name" value="${TAK_SERVER_NAME:-takserver}"/>
<Parameter name="onReceiveDelete" value="false"/>
</Configuration>
<Contents>
<Content ignore="false" zipEntry="content/blueteam.pref"/>
$(printf '%s' "$MAP_ENTRIES")<Content ignore="false" zipEntry="content/${CLIENT_CERT_NAME}.p12"/>
<Content ignore="false" zipEntry="content/truststore-root.p12"/>
<Content ignore="false" zipEntry="TAK_defaults.pref"/>
</Contents>
</MissionPackageManifest>
MANIFEST

cd ${CR}

CAPASS=${CA_PASS} PASS="${CLIENT_CERT_PASSWORD}" bash makeCert.sh client "${CLIENT_CERT_NAME}"

cp ${CR}/files/${CLIENT_CERT_NAME}.p12 ${WORK_DIR}/content/

cp ${CR}/files/truststore-root.p12 ${WORK_DIR}/content/

cd $WORK_DIR

zip -r ${tmp_dir}/${CLIENT_CERT_NAME}.zip ./

if [ -f ${ZIPTGT}/${CLIENT_CERT_NAME}.zip ]

then

echo "${CLIENT_CERT_NAME} Was created while we worked !"

exit 1

fi

mv ${tmp_dir}/${CLIENT_CERT_NAME}.zip ${ZIPTGT}/

rm -rf $tmp_dir
