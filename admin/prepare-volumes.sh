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
    /opt/tak/data/replay \
    /opt/tak/data/certs/files/clientpkgs \
    /opt/tak/plugins; do
    chgrp -R "$TAK_GID" "$path"
    chmod -R g+rwX,o-rwx "$path"
    chmod g+s "$path"
done

# Preserve the bind mount's host owner while granting the shared group access.
chgrp -R "$TAK_GID" /opt/tak/maps
chmod -R g+rwX,o-rwx /opt/tak/maps
chmod g+s /opt/tak/maps

chown -R "$ADMIN_UID:$ADMIN_GID" /tmp/admin
chmod 700 /tmp/admin
chown -R "$NGINX_UID:$NGINX_GID" /etc/nginx/ssl
chmod 700 /etc/nginx/ssl
