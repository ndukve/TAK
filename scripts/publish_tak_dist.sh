#!/usr/bin/env bash
# Builds a minimal image containing your tak.gov-downloaded TAK Server zip
# and pushes it to GHCR, so any server can `docker pull` it during build
# instead of you scp-ing the zip by hand. One-time per version.
#
# Requires: docker login ghcr.io -u <your-github-username>  (PAT with
# write:packages scope) — run that once before this script.
#
# Usage: ./scripts/publish_tak_dist.sh <version>
#   ./scripts/publish_tak_dist.sh 5.7-RELEASE-43
set -euo pipefail

VERSION="${1:?Usage: $0 <version, e.g. 5.7-RELEASE-43>}"
GHCR_OWNER="${GHCR_OWNER:-ndukve}"
IMAGE="ghcr.io/${GHCR_OWNER}/tak-server-dist:${VERSION}"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$SCRIPT_DIR/takserver-dist"

ls "$DIST_DIR"/takserver-docker-*.zip >/dev/null 2>&1 \
    || { echo "No takserver-docker-*.zip found in takserver-dist/" >&2; exit 1; }

echo "Building $IMAGE..."
docker build -t "$IMAGE" -f "$SCRIPT_DIR/docker/tak-dist.Dockerfile" "$DIST_DIR"

echo "Pushing $IMAGE..."
docker push "$IMAGE"

echo ""
echo "Done: $IMAGE"
echo "Make sure the package is set to Private under GitHub -> your profile ->"
echo "Packages, and that any machine building this repo has run:"
echo "  docker login ghcr.io -u ${GHCR_OWNER}"
