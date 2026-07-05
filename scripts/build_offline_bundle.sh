#!/usr/bin/env bash
# Builds a self-contained bundle for closed/air-gapped networks (e.g.
# governmental networks that can't reach GitHub/Docker Hub/apt at all, or
# offgrid comms where you can't run an installer that pulls from the internet).
#
# Run this on a machine WITH internet — it builds normally (same as
# install.sh) and packages the finished images + deployment files into one
# folder. Copy that folder into the closed network by hand (USB, approved
# transfer, whatever your environment allows) and run install-offline.sh
# from inside it — no network calls happen during that install.
#
# Usage: ./scripts/build_offline_bundle.sh [output-dir]
set -euo pipefail

DOCKER_VERSION="29.6.1"
COMPOSE_VERSION="v5.3.0"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

BUNDLE_DIR="${1:-$SCRIPT_DIR/offline-bundle}"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/images" "$BUNDLE_DIR/docker-bin"

echo "Fetching Docker ${DOCKER_VERSION} static binaries + Compose ${COMPOSE_VERSION} plugin..."
curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
    -o "$BUNDLE_DIR/docker-bin/docker.tgz"
curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o "$BUNDLE_DIR/docker-bin/docker-compose"
chmod +x "$BUNDLE_DIR/docker-bin/docker-compose"
cp docker/containerd.service docker/docker.service "$BUNDLE_DIR/docker-bin/"

echo "Building images (needs internet for this step only)..."
export GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
docker compose build

echo "Saving images into $BUNDLE_DIR/images ..."
docker save -o "$BUNDLE_DIR/images/takserver.tar"         takserver:local
docker save -o "$BUNDLE_DIR/images/admin.tar"             admin:local
docker save -o "$BUNDLE_DIR/images/nginx.tar"             nginx:alpine
docker save -o "$BUNDLE_DIR/images/postgis.tar"           postgis/postgis:15-3.3
docker save -o "$BUNDLE_DIR/images/docker-socket-proxy.tar" tecnativa/docker-socket-proxy:v0.4.2

echo "Copying deployment files..."
cp docker-compose.yml install-offline.sh Makefile "$BUNDLE_DIR/"
cp -r scripts templates "$BUNDLE_DIR/"
mkdir -p "$BUNDLE_DIR/admin"
cp -r admin/nginx "$BUNDLE_DIR/admin/"
mkdir -p "$BUNDLE_DIR/packages/tak-maps"

echo ""
echo "Bundle ready: $BUNDLE_DIR"
echo "Copy this whole folder to the offline machine, then run: ./install-offline.sh"
