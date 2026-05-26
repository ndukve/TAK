#!/bin/bash
# ============================================================
# generate_user.sh — Generate an iTAK / ATAK data package
# Usage: ./generate_user.sh <username>
#
# Output: $DATA_DIR/certs/clientPackages/<username>.zip
# Import: Settings → Network → Servers → + → Upload Server Package
# Serve:  make serve-packages
# ============================================================

set -euo pipefail

source "$(dirname "$0")/.env"

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

DATA_DIR="${DATA_DIR:-/opt/fts}"
CERT_DIR="$DATA_DIR/certs"
PKG_DIR="$CERT_DIR/clientPackages"
CERT_PASS="${CERT_PASSWORD:-atakatak}"
TMP_DIR="/tmp/tak-pkg-${USERNAME}"

# ── Detect OpenSSL version (3.x needs -legacy for TAK client compatibility) ──
OPENSSL_MAJOR=$(openssl version | awk '{print $2}' | cut -d. -f1)
P12_LEGACY=""
[ "$OPENSSL_MAJOR" -ge 3 ] && P12_LEGACY="-legacy"

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [ ! -f "$CERT_DIR/ca.pem" ] || [ ! -f "$CERT_DIR/ca.key" ]; then
    echo "[!] CA certs not found at $CERT_DIR"
    echo "    Start FTS at least once so it generates its own CA:"
    echo "      make up && docker logs freetakserver -f"
    echo "    Wait for 'FTS started' then re-run this script."
    exit 1
fi

if [ ! -f "$CERT_DIR/server.p12" ]; then
    echo "[!] server.p12 not found at $CERT_DIR — start FTS first."
    exit 1
fi

mkdir -p "$PKG_DIR"

# ── Fix permissions so we can read FTS certs ──────────────────────────────────
chmod -R 777 "$DATA_DIR" 2>/dev/null || true

# ── User certificate (signed by FTS's own CA) ─────────────────────────────────
echo "[*] Generating cert for user: $USERNAME"

openssl genrsa -out "$CERT_DIR/${USERNAME}.key" 2048 2>/dev/null
openssl req -new \
    -key "$CERT_DIR/${USERNAME}.key" \
    -out "$CERT_DIR/${USERNAME}.csr" \
    -subj "/CN=${USERNAME}/O=FreeTAKServer/C=US" 2>/dev/null
openssl x509 -req -sha256 \
    -days "${USER_CERT_VALIDITY_DAYS:-365}" \
    -in  "$CERT_DIR/${USERNAME}.csr" \
    -CA  "$CERT_DIR/ca.pem" \
    -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/${USERNAME}.crt" 2>/dev/null
rm "$CERT_DIR/${USERNAME}.csr"

openssl pkcs12 $P12_LEGACY -export \
    -in      "$CERT_DIR/${USERNAME}.crt" \
    -inkey   "$CERT_DIR/${USERNAME}.key" \
    -certfile "$CERT_DIR/ca.pem" \
    -out "$CERT_DIR/${USERNAME}.p12" \
    -passout "pass:$CERT_PASS" 2>/dev/null

echo "[✓] User cert: $CERT_DIR/${USERNAME}.p12"

# ── Assemble iTAK data package ─────────────────────────────────────────────────
# IMPORTANT: iTAK-specific format rules (different from ATAK):
#   - Cert files go in a 'certs/' subfolder inside the zip
#   - manifest.xml is at the zip root (not MANIFEST/manifest.xml)
#   - zipEntry attributes use backslash paths ('certs\file') — required by iTAK parser
#   - CA trust cert = server.p12 from FTS (contains the CA chain)
#   - Pref cert paths use 'cert/' (no 's') — iTAK's internal cert store path after import
#   - TCP connection on 8087 (SSL on 8089 still drops; use TCP)

echo "[*] Building iTAK data package..."
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/certs"

# FTS server.p12 is used as the CA trust cert — it contains the full cert chain.
# Including the private key here is unavoidable since FTS doesn't separate them,
# but iTAK only uses the CA portion for trust verification.
cp "$CERT_DIR/server.p12"         "$TMP_DIR/certs/server.p12"
cp "$CERT_DIR/${USERNAME}.p12"    "$TMP_DIR/certs/${USERNAME}.p12"

# Connection preference: TCP (reliable), cert paths use 'cert/' (iTAK internal store)
cat > "$TMP_DIR/certs/tak-server.pref" << EOF
<?xml version='1.0' encoding='ASCII' standalone='yes'?>
<preferences>
  <preference version="1" name="cot_streams">
    <entry key="count" class="class java.lang.Integer">1</entry>
    <entry key="description0" class="class java.lang.String">FreeTAKServer</entry>
    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
    <entry key="connectString0" class="class java.lang.String">${FTS_IP}:${COT_PORT:-8087}:tcp</entry>
  </preference>
  <preference version="1" name="com.atakmap.app_preferences">
    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
    <entry key="caLocation" class="class java.lang.String">cert/server.p12</entry>
    <entry key="caPassword" class="class java.lang.String">${CERT_PASS}</entry>
    <entry key="clientPassword" class="class java.lang.String">${CERT_PASS}</entry>
    <entry key="certificateLocation" class="class java.lang.String">cert/${USERNAME}.p12</entry>
    <entry key="network_mesh_detection" class="class java.lang.Boolean">false</entry>
  </preference>
</preferences>
EOF

UUID=$(cat /proc/sys/kernel/random/uuid)

# Manifest at zip root; backslash paths in zipEntry are required by iTAK's parser.
# printf handles literal backslashes correctly where heredoc would interpret them.
printf '<MissionPackageManifest version="2">\n' > "$TMP_DIR/manifest.xml"
printf '<Configuration>\n' >> "$TMP_DIR/manifest.xml"
printf '  <Parameter name="uid" value="%s"/>\n' "$UUID" >> "$TMP_DIR/manifest.xml"
printf '  <Parameter name="name" value="%s_DP"/>\n' "$USERNAME" >> "$TMP_DIR/manifest.xml"
printf '  <Parameter name="onReceiveDelete" value="true"/>\n' >> "$TMP_DIR/manifest.xml"
printf '</Configuration>\n' >> "$TMP_DIR/manifest.xml"
printf '<Contents>\n' >> "$TMP_DIR/manifest.xml"
printf '  <Content ignore="false" zipEntry="certs\\tak-server.pref"/>\n' >> "$TMP_DIR/manifest.xml"
printf '  <Content ignore="false" zipEntry="certs\\server.p12"/>\n' >> "$TMP_DIR/manifest.xml"
printf '  <Content ignore="false" zipEntry="certs\\%s.p12"/>\n' "$USERNAME" >> "$TMP_DIR/manifest.xml"
printf '</Contents>\n' >> "$TMP_DIR/manifest.xml"
printf '</MissionPackageManifest>\n' >> "$TMP_DIR/manifest.xml"

# Zip the package (forward-slash arc paths; the backslashes only exist inside manifest.xml)
OUT_ZIP="$PKG_DIR/${USERNAME}.zip"
python3 - << PYEOF
import zipfile, os

pkg_dir = "$TMP_DIR"
out_zip = "$OUT_ZIP"

with zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(pkg_dir):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for fname in sorted(files):
            if fname.startswith('.'):
                continue
            abs_path = os.path.join(root, fname)
            arc_name = os.path.relpath(abs_path, pkg_dir).replace(os.sep, '/')
            z.write(abs_path, arc_name)

print(f"Package: {out_zip}")
PYEOF

rm -rf "$TMP_DIR"
chmod -R 777 "$DATA_DIR" 2>/dev/null || true

echo ""
echo "[✓] Done!  $OUT_ZIP"
echo ""
echo "    Serve to device (run from LXC):"
echo "      make serve-packages"
echo "    Direct URL: http://${FTS_IP}:8888/${USERNAME}.zip"
echo ""
echo "    Import in iTAK:"
echo "      Settings → Network → Servers → + → Upload Server Package"
