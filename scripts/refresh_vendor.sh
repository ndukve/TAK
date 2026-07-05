#!/usr/bin/env bash
# Every base image this project depends on is sourced from a local, durable
# copy in takserver-dist/ — never a live Docker Hub tag pulled fresh at build
# time, for either the online build path or the offline bundle. The first
# time a copy doesn't exist yet, it's restored from your own GHCR mirror
# (ghcr.io/ndukve/tak-vendor) if reachable, falling back to a direct Docker
# Hub pull only if that mirror doesn't have it yet. Either way, once fetched
# it's saved here and every build after that, online or offline, loads from
# that exact saved copy — no drift, no dependency on Docker Hub being up.
#
# Sourced by install.sh/update.sh/health.sh/install-offline.sh for
# load_vendored_images(). Run directly, it refreshes a vendored copy: pulls
# it fresh, overwrites the local tar, and pushes to your GHCR mirror so any
# server can restore it later without depending on Docker Hub being
# reachable. Manual, deliberate — never run automatically.
#
# Requires (only to refresh/push): docker login ghcr.io (write:packages).
#
# Usage:
#   ./scripts/refresh_vendor.sh                    # refresh all 7 base images
#   ./scripts/refresh_vendor.sh nginx_alpine.tar   # refresh just one
#   ./scripts/refresh_vendor.sh tak                # rebuild+push the TAK zip wrapper
set -euo pipefail

GHCR_VENDOR_REPO="ghcr.io/ndukve/tak-vendor"

VENDORED_IMAGES=(
    "nginx_alpine.tar|nginx:alpine|nginx-alpine"
    "eclipse-temurin_17-noble.tar|eclipse-temurin:17-noble|eclipse-temurin-17-noble"
    "hairyhenderson_gomplate_stable.tar|hairyhenderson/gomplate:stable|gomplate-stable"
    "node_20-slim.tar|node:20-slim|node-20-slim"
    "python_3.11-slim.tar|python:3.11-slim|python-3.11-slim"
    "postgis_postgis_15-3.3.tar|postgis/postgis:15-3.3|postgis-15-3.3"
    "tecnativa_docker-socket-proxy_v0.4.2.tar|tecnativa/docker-socket-proxy:v0.4.2|docker-socket-proxy-v0.4.2"
)

load_vendored_images() {
    local dir="${1:-takserver-dist}" repo_root entry name ref ghcr_tag f
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    mkdir -p "$dir"

    for entry in "${VENDORED_IMAGES[@]}"; do
        IFS='|' read -r name ref ghcr_tag <<< "$entry"
        f="$dir/$name"
        if [ ! -e "$f" ]; then
            echo "Vendoring $ref (first time only, saved to $f)..."
            if docker pull "$GHCR_VENDOR_REPO:$ghcr_tag" >/dev/null 2>&1; then
                docker tag "$GHCR_VENDOR_REPO:$ghcr_tag" "$ref"
            else
                docker pull "$ref" >/dev/null
            fi
            docker save -o "$f" "$ref"
        fi
        docker load -i "$f" >/dev/null
    done

    # TAK Server zip — vendored from your own tak.gov download, not pulled.
    local zip version tak_tar
    zip=$(ls "$dir"/takserver-docker-*.zip 2>/dev/null | head -1) || true
    if [ -n "${zip:-}" ]; then
        version=$(basename "$zip" .zip | sed 's/^takserver-docker-//')
        tak_tar="$dir/tak-server-dist_${version}.tar"
        if [ ! -e "$tak_tar" ]; then
            echo "Vendoring TAK Server ${version} (first time only)..."
            docker build -t "tak-server-dist:${version}" -f "$repo_root/docker/tak-dist.Dockerfile" "$dir" >/dev/null
            docker save -o "$tak_tar" "tak-server-dist:${version}"
        fi
        docker load -i "$tak_tar" >/dev/null
    fi
}

# ── CLI mode (only when run directly, not when sourced for the function above) ──
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    DIST_DIR="$SCRIPT_DIR/takserver-dist"
    TARGET="${1:-}"
    mkdir -p "$DIST_DIR"

    if [ "$TARGET" = "tak" ]; then
        zip=$(ls "$DIST_DIR"/takserver-docker-*.zip 2>/dev/null | head -1) \
            || { echo "No takserver-docker-*.zip found in takserver-dist/" >&2; exit 1; }
        version=$(basename "$zip" .zip | sed 's/^takserver-docker-//')
        image="tak-server-dist:${version}"

        echo "Building ${image}..."
        docker build -t "$image" -f "$SCRIPT_DIR/docker/tak-dist.Dockerfile" "$DIST_DIR"
        docker save -o "$DIST_DIR/tak-server-dist_${version}.tar" "$image"

        docker tag "$image" "ghcr.io/ndukve/tak-server-dist:${version}"
        docker push "ghcr.io/ndukve/tak-server-dist:${version}"

        echo ""
        echo "Done: ghcr.io/ndukve/tak-server-dist:${version} (keep this Private)"
        exit 0
    fi

    for entry in "${VENDORED_IMAGES[@]}"; do
        IFS='|' read -r name ref ghcr_tag <<< "$entry"
        [ -n "$TARGET" ] && [ "$TARGET" != "$name" ] && continue

        echo "Refreshing ${ref}..."
        docker pull "$ref"
        docker save -o "$DIST_DIR/$name" "$ref"

        docker tag "$ref" "$GHCR_VENDOR_REPO:$ghcr_tag"
        docker push "$GHCR_VENDOR_REPO:$ghcr_tag"
    done

    echo ""
    echo "Done. First time: set ghcr.io/ndukve/tak-vendor (and tak-server-dist)"
    echo "to Private under GitHub -> your profile -> Packages."
fi
