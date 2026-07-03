#!/bin/sh
set -e
apk add --no-cache openssl >/dev/null 2>&1
mkdir -p /etc/nginx/ssl

ADDR="${TAK_SERVER_ADDRESS:-localhost}"
if echo "$ADDR" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    SAN="IP:${ADDR},IP:127.0.0.1,DNS:localhost"
else
    SAN="DNS:${ADDR},DNS:localhost,IP:127.0.0.1"
fi

# Regenerate whenever there's no cert yet, or the existing one predates this
# SAN logic (or the server address changed) — modern browsers (iOS Safari
# included) hard-reject certs with no Subject Alternative Name, often with
# no "proceed anyway" option at all, which looks exactly like "this site
# needs a client certificate" even though none is required.
NEEDS_REGEN=0
if [ ! -f /etc/nginx/ssl/cert.pem ]; then
    NEEDS_REGEN=1
elif ! openssl x509 -in /etc/nginx/ssl/cert.pem -noout -ext subjectAltName 2>/dev/null | grep -q "$ADDR"; then
    NEEDS_REGEN=1
fi

if [ "$NEEDS_REGEN" = "1" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout /etc/nginx/ssl/key.pem \
        -out  /etc/nginx/ssl/cert.pem \
        -subj "/CN=${ADDR}" \
        -addext "subjectAltName=${SAN}"
fi
exec nginx -g 'daemon off;'
