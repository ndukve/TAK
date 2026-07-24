#!/bin/sh
# Runs once after TAK initialization.  Grant the non-root admin only the shared
# volume access it needs, and prepare nginx's private TLS volume.
set -eu

TAK_GID=10000
ADMIN_UID=10001
ADMIN_GID=10001
NGINX_UID=101
NGINX_GID=101

mkdir -p \
    /opt/tak/data/branding \
    /opt/tak/data/basemap-cache \
    /opt/tak/data/replay \
    /opt/tak/data/certs/files/clientpkgs \
    /opt/tak/plugins \
    /opt/tak/maps \
    /tmp/admin \
    /etc/nginx/ssl

# Certificate material is readable, but not directly writable, by the admin.
# Certificate creation and revocation continue to go through the allowlisted
# exec endpoint in the TAK container.
chgrp -R "$TAK_GID" /opt/tak/data/certs/files
chmod -R g+rX,o-rwx /opt/tak/data/certs/files

# These are the only TAK-facing paths the admin writes directly.  The setgid
# bit preserves the shared TAK group on newly uploaded/generated files.
for path in \
    /opt/tak/data/branding \
    /opt/tak/data/basemap-cache \
    /opt/tak/data/replay \
    /opt/tak/data/certs/files/clientpkgs \
    /opt/tak/plugins; do
    chgrp -R "$TAK_GID" "$path"
    chmod -R g+rwX,o-rwx "$path"
    chmod g+s "$path"
done

# ATAK already trusts the TAK root CA from its enrollment package. Sign the
# admin proxy certificate with that CA so proxied/cached basemap tiles load in
# the map engine without a separate self-signed-certificate exception.
ADDR="${TAK_SERVER_ADDRESS:-localhost}"
NEEDS_PROXY_CERT=0
if [ ! -f /etc/nginx/ssl/cert.pem ]; then
    NEEDS_PROXY_CERT=1
elif ! openssl x509 -in /etc/nginx/ssl/cert.pem -noout -ext subjectAltName 2>/dev/null | grep -q "$ADDR"; then
    NEEDS_PROXY_CERT=1
elif ! openssl verify -CAfile /opt/tak/data/certs/files/ca.pem /etc/nginx/ssl/cert.pem >/dev/null 2>&1; then
    NEEDS_PROXY_CERT=1
fi
if [ "$NEEDS_PROXY_CERT" = "1" ]; then
    if echo "$ADDR" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        SAN="IP:${ADDR},IP:127.0.0.1,DNS:localhost"
    else
        SAN="DNS:${ADDR},DNS:localhost,IP:127.0.0.1"
    fi
    openssl req -new -nodes -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/key.pem \
        -out /tmp/admin/admin-proxy.csr \
        -subj "/CN=${ADDR}"
    printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\n' "$SAN" >/tmp/admin/admin-proxy.ext
    SERIAL="0x$(openssl rand -hex 16)"
    openssl x509 -req -days 730 \
        -in /tmp/admin/admin-proxy.csr \
        -CA /opt/tak/data/certs/files/ca.pem \
        -CAkey /opt/tak/data/certs/files/ca-do-not-share.key \
        -passin "pass:${CA_PASS}" \
        -set_serial "$SERIAL" \
        -extfile /tmp/admin/admin-proxy.ext \
        -out /etc/nginx/ssl/cert.pem
    cat /opt/tak/data/certs/files/ca.pem >>/etc/nginx/ssl/cert.pem
    rm -f /tmp/admin/admin-proxy.csr /tmp/admin/admin-proxy.ext
fi

# Preserve the bind mount's host owner while granting the shared group access.
chgrp -R "$TAK_GID" /opt/tak/maps
chmod -R g+rwX,o-rwx /opt/tak/maps
chmod g+s /opt/tak/maps

chown -R "$ADMIN_UID:$ADMIN_GID" /tmp/admin
chmod 700 /tmp/admin
chown -R "$NGINX_UID:$NGINX_GID" /etc/nginx/ssl
chmod 700 /etc/nginx/ssl
chmod 600 /etc/nginx/ssl/key.pem 2>/dev/null || true
chmod 644 /etc/nginx/ssl/cert.pem 2>/dev/null || true
