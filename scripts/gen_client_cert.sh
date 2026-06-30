#!/usr/bin/env -S /bin/bash
# Generate client certificate only. Does not package or authorize.
# Password is written to <name>.certpass so make_pkg_zip.sh can read it.

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

TR=/opt/tak
CR=${TR}/data/certs

[ -n "$CLIENT_CERT_NAME" ] || fail "CLIENT_CERT_NAME not set"

if [ -f "${CR}/files/${CLIENT_CERT_NAME}.key" ]; then
    fail "${CLIENT_CERT_NAME} cert already exists"
fi

export CLIENT_CERT_PASSWORD=$(pwgen -cn1 20 1) # pragma: allowlist secret

info "Generating certificate for ${CLIENT_CERT_NAME}"
cd ${CR}
CAPASS=${CA_PASS} PASS="${CLIENT_CERT_PASSWORD}" bash makeCert.sh client "${CLIENT_CERT_NAME}" >/dev/null

echo "${CLIENT_CERT_PASSWORD}" > "${CR}/files/${CLIENT_CERT_NAME}.certpass"
chmod 600 "${CR}/files/${CLIENT_CERT_NAME}.certpass"

ok "Device cert ready: ${CLIENT_CERT_NAME}.p12"
