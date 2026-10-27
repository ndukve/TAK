#!/usr/bin/env bash
# Reissue the TAK server leaf certificate with configured client endpoints in
# its SAN, keeping the existing CA and internal CN. Back up first: this
# replaces takserver's key, certificate, PKCS#12 and JKS files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${TAK_ENV_FILE:-$SCRIPT_DIR/takserver.env}"
DC=(docker compose --env-file "$ENV_FILE")

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || fail "TAK env file not found"
for key in TAK_SERVER_ADDRESS CA_PASS TAKSERVER_CERT_PASS; do
    grep -q "^${key}=." "$ENV_FILE" || fail "${key} is missing or empty in the TAK env file"
done

"${DC[@]}" exec -T takserver_config test -s /opt/tak/data/certs/files/takserver.pem \
    || fail "Existing TAK server certificate was not found"

printf 'Current server certificate metadata:\n'
"${DC[@]}" exec -T takserver_config openssl x509 \
    -in /opt/tak/data/certs/files/takserver.pem -noout -subject -issuer -dates -ext subjectAltName
printf '\nThis replaces the TAK server certificate and key, then restarts its TLS services.\n'
printf 'Create a backup with scripts/backup.sh before continuing.\n'
read -r -p 'Type REISSUE TAK SERVER CERT to continue: ' confirmation
[ "$confirmation" = "REISSUE TAK SERVER CERT" ] || fail "Confirmation did not match; no changes made"

# The command is single-quoted intentionally so secrets and endpoint settings
# expand inside the container, not in this host shell.
# shellcheck disable=SC2016
"${DC[@]}" exec -T takserver_config bash -lc '
    set -e
    cd /opt/tak/certs
    test -n "${TAK_SERVER_ADDRESS:-}" || { echo "TAK_SERVER_ADDRESS is missing" >&2; exit 1; }
    CAPASS="$CA_PASS" PASS="$TAKSERVER_CERT_PASS" bash /opt/scripts/makeCert.sh server takserver >/dev/null
    cert=/opt/tak/data/certs/files/takserver.pem
    check_name() {
        if [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ || "$1" == *:* ]]; then
            openssl x509 -in "$cert" -noout -checkip "$1" >/dev/null
        else
            openssl x509 -in "$cert" -noout -checkhost "$1" >/dev/null
        fi
    }
    check_name "$TAK_SERVER_ADDRESS"
    if [ -n "${TAK_SERVER_ADDRESS_LAN:-}" ]; then check_name "$TAK_SERVER_ADDRESS_LAN"; fi
    jks=/opt/tak/data/certs/files/takserver.jks
    test -s "$jks"
    pem_fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha256)
    jks_fingerprint=$(keytool -exportcert -keystore "$jks" -storepass "$TAKSERVER_CERT_PASS" -alias takserver | openssl x509 -noout -fingerprint -sha256)
    [ "$jks_fingerprint" = "$pem_fingerprint" ] || { echo "JKS does not contain the newly issued server certificate" >&2; exit 1; }
' || fail "Certificate issuance or SAN verification failed; inspect before restarting TAK"

"${DC[@]}" restart takserver_config takserver_messaging takserver_api \
    || fail "Certificate was issued, but TAK service restart failed; inspect service status and backup"

printf 'TAK server certificate renewed and TLS services restarted.\n'
