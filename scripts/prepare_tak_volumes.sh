#!/bin/sh
# Runs once as root, without a network or writable root filesystem, before the
# unprivileged TAK services start.  This also migrates volumes created by older
# releases whose containers ran as root.
set -eu

TAK_UID=10000
TAK_GID=10000

for path in /opt/tak/data /opt/tak/plugins /opt/tak/conf/plugins; do
    mkdir -p "$path"
    chown -R "$TAK_UID:$TAK_GID" "$path"
    chmod -R u+rwX,g+rX,o-rwx "$path"
done
