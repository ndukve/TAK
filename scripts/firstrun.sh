#!/usr/bin/env -S /bin/bash
# shellcheck shell=bash

if [ -f /opt/tak/data/firstrun.done ]; then
    echo "  ✓  First run already done"
    exit 0
fi

TR=/opt/tak
CR=${TR}/certs

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

# Seed initial certificate data
if [[ ! -d "${TR}/data/certs" ]]; then
    mkdir -p "${TR}/data/certs"
fi

if [[ ! -f "${TR}/data/certs/cert-metadata.sh" ]]; then
    info "Copying initial certificate configuration"
    cp -R ${TR}/certs/* ${TR}/data/certs/
    ok "Certificate configuration seeded"
else
    ok "Using existing certificates"
fi

# Symlink certs into data dir
if [[ ! -L "${TR}/certs" ]]; then
    mv ${TR}/certs ${TR}/certs.orig
    ln -f -s "${TR}/data/certs/" "${TR}/certs"
fi

# Remove hardcoded country code
sed -i.orig "s|COUNTRY=US|COUNTRY=\${COUNTRY}|g" ${CR}/cert-metadata.sh

# Override distribution cert script
cp /opt/scripts/makeCert.sh ${CR}/

# Symlink logs
if [[ ! -d "${TR}/data/logs" ]]; then
    mkdir -p "${TR}/data/logs"
fi
if [[ ! -L "${TR}/logs" ]]; then
    ln -f -s "${TR}/data/logs/" "${TR}/logs"
fi

cd ${CR}

if [[ ! -f "${CR}/files/root-ca.pem" ]]; then
    info "Generating root CA: ${CA_NAME}"
    CAPASS=${CA_PASS} bash makeRootCa.sh --ca-name "${CA_NAME}" >/dev/null
    ok "Root CA ready"
else
    ok "Using existing root CA"
fi

if [[ ! -f "${CR}/files/takserver.pem" ]]; then
    info "Generating server certificate"
    CAPASS=${CA_PASS} PASS="${TAKSERVER_CERT_PASS}" bash makeCert.sh server takserver >/dev/null
    ok "Server certificate ready"
else
    ok "Using existing server certificate"
fi

if [[ ! -f "${CR}/files/${ADMIN_CERT_NAME}.pem" ]]; then
    info "Generating admin certificate: ${ADMIN_CERT_NAME}"
    CAPASS=${CA_PASS} PASS="${ADMIN_CERT_PASS}" bash makeCert.sh client "${ADMIN_CERT_NAME}" >/dev/null
    ok "Admin certificate ready"
else
    ok "Using existing admin certificate: ${ADMIN_CERT_NAME}"
fi

# TAK services share the fixed 10000:10000 runtime identity.  The permissions
# initializer migrates older root-owned volumes before this script runs.
chmod -R 750 ${TR}/data/

info "Waiting for PostgreSQL"
WAITFORIT_TIMEOUT=60 /usr/bin/wait-for-it.sh ${POSTGRES_ADDRESS}:5432 -- true
ok "PostgreSQL ready"

info "Running database schema upgrade"
java -jar ${TR}/db-utils/SchemaManager.jar \
    -url jdbc:postgresql://${POSTGRES_ADDRESS}:5432/${POSTGRES_DB} \
    -user ${POSTGRES_USER} -password ${POSTGRES_PASSWORD} upgrade
ok "Schema upgrade complete"

date -u +"%Y%m%dT%H%M" >/opt/tak/data/firstrun.done
ok "First run complete"
