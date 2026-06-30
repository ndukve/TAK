#!/usr/bin/env bash
# Build an offline TAK Server installer ISO.
#
# Prerequisites (on the build machine):
#   sudo apt install xorriso squashfs-tools genisoimage
#   docker          (with images already built: docker compose build)
#
# Output: tak-server-offline-<date>.iso
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$(mktemp -d)"
OUTPUT_ISO="${SCRIPT_DIR}/tak-server-offline-$(date +%Y%m%d).iso"

UBUNTU_ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
UBUNTU_ISO="${SCRIPT_DIR}/ubuntu-22.04-server.iso"

DOCKER_IMAGES=(
    "takserver:local"
    "postgis/postgis:15-3.3"
    "python:3.11-slim"
    "nginx:alpine"
)

# Docker packages to download for offline install
DOCKER_PKG_URL="https://download.docker.com/linux/ubuntu/dists/jammy/pool/stable/amd64"
DOCKER_DEBS=(
    "containerd.io_1.7.15-1_amd64.deb"
    "docker-ce-cli_26.1.4-1~ubuntu.22.04~jammy_amd64.deb"
    "docker-ce_26.1.4-1~ubuntu.22.04~jammy_amd64.deb"
    "docker-compose-plugin_2.27.1-1~ubuntu.22.04~jammy_amd64.deb"
)

err() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO]  $*"; }

# ── Check tools ──────────────────────────────────────────────────────────────
for cmd in xorriso docker curl; do
    command -v "$cmd" &>/dev/null || err "Missing required tool: $cmd"
done

info "Build directory: $WORK_DIR"

# ── Download Ubuntu ISO ──────────────────────────────────────────────────────
if [[ ! -f "$UBUNTU_ISO" ]]; then
    info "Downloading Ubuntu 22.04 server ISO (~1.5 GB)..."
    curl -L --progress-bar -o "$UBUNTU_ISO" "$UBUNTU_ISO_URL"
fi

# ── Extract ISO ──────────────────────────────────────────────────────────────
info "Extracting ISO..."
ISO_EXTRACT="$WORK_DIR/iso"
mkdir -p "$ISO_EXTRACT"
xorriso -osirrox on -indev "$UBUNTU_ISO" -extract / "$ISO_EXTRACT" 2>/dev/null
chmod -R u+w "$ISO_EXTRACT"

# ── Inject autoinstall config ────────────────────────────────────────────────
info "Injecting autoinstall config..."
cp "$SCRIPT_DIR/autoinstall/user-data" "$ISO_EXTRACT/user-data"
cp "$SCRIPT_DIR/autoinstall/meta-data" "$ISO_EXTRACT/meta-data"

# Patch grub to boot autoinstall by default
GRUB_CFG="$ISO_EXTRACT/boot/grub/grub.cfg"
if [[ -f "$GRUB_CFG" ]]; then
    sed -i 's/timeout=.*/timeout=5/' "$GRUB_CFG"
    # Prepend autoinstall entry
    AUTOINSTALL_ENTRY='
menuentry "TAK Server - Automated Install" {
    set gfxpayload=keep
    linux   /casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/ quiet ---
    initrd  /casper/initrd
}
'
    echo "$AUTOINSTALL_ENTRY" | cat - "$GRUB_CFG" > /tmp/grub.tmp && mv /tmp/grub.tmp "$GRUB_CFG"
fi

# ── Bundle Docker .deb packages ──────────────────────────────────────────────
info "Downloading Docker packages for offline install..."
DEB_DIR="$ISO_EXTRACT/docker-debs"
mkdir -p "$DEB_DIR"
for deb in "${DOCKER_DEBS[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/cache/$deb" ]]; then
        mkdir -p "$SCRIPT_DIR/cache"
        curl -L --progress-bar -o "$SCRIPT_DIR/cache/$deb" "$DOCKER_PKG_URL/$deb" || \
            info "Warning: could not download $deb — may need internet on target"
    fi
    cp "$SCRIPT_DIR/cache/$deb" "$DEB_DIR/" 2>/dev/null || true
done

# ── Save Docker images ───────────────────────────────────────────────────────
info "Saving Docker images (this may take several minutes)..."
IMAGES_TAR="$SCRIPT_DIR/cache/docker-images.tar.gz"
if [[ ! -f "$IMAGES_TAR" ]] || [[ "${FORCE_REBUILD_IMAGES:-}" == "1" ]]; then
    # Check all images exist
    for img in "${DOCKER_IMAGES[@]}"; do
        docker image inspect "$img" &>/dev/null || \
            err "Image not found: $img — run 'docker compose build' first"
    done
    docker save "${DOCKER_IMAGES[@]}" | gzip -9 > "$IMAGES_TAR"
    info "Images saved: $(du -sh "$IMAGES_TAR" | cut -f1)"
fi

# ── Bundle repo files ────────────────────────────────────────────────────────
info "Bundling TAK server files..."
TAK_DIR="$ISO_EXTRACT/tak-server"
mkdir -p "$TAK_DIR"

# Copy repo, excluding build artifacts and large files already bundled
rsync -a --exclude='.git' \
         --exclude='node_modules' \
         --exclude='admin/ui/dist' \
         --exclude='build-iso/cache' \
         --exclude='build-iso/*.iso' \
         --exclude='*.tar.gz' \
         --exclude='__pycache__' \
         "$REPO_DIR/" "$TAK_DIR/"

# Place images tar where firstboot.sh expects it
mkdir -p "$TAK_DIR/build-iso"
cp "$IMAGES_TAR" "$TAK_DIR/build-iso/docker-images.tar.gz"

# ── Rebuild ISO ──────────────────────────────────────────────────────────────
info "Building ISO..."
xorriso -as mkisofs \
    -r -V "TAK-SERVER-OFFLINE" \
    -o "$OUTPUT_ISO" \
    -J -joliet-long \
    -b boot/grub/i386-pc/eltorito.img \
    -c boot/grub/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --grub2-boot-info \
    --grub2-mbr "$ISO_EXTRACT/boot/grub/i386-pc/boot_hybrid.img" \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -isohybrid-apm-hfsplus \
    "$ISO_EXTRACT" 2>/dev/null

info "Done: $OUTPUT_ISO ($(du -sh "$OUTPUT_ISO" | cut -f1))"
info ""
info "Write to USB: sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress && sync"

# Cleanup
rm -rf "$WORK_DIR"
