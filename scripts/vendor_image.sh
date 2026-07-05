#!/usr/bin/env bash
# Check Docker Hub for available tags of a base image, let you pick one,
# pull it, and save it into takserver-dist/ as a .tar — so the build uses
# your chosen, vendored copy instead of always pulling latest at build time.
#
# Usage: ./scripts/vendor_image.sh <image> [tag]
#   ./scripts/vendor_image.sh nginx                 # lists tags, prompts
#   ./scripts/vendor_image.sh nginx alpine           # pulls/saves that tag directly
#
# After saving, update the matching FROM/image line in Dockerfile,
# admin/Dockerfile, or docker-compose.yml to match the tag you picked.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$SCRIPT_DIR/takserver-dist"

IMAGE="${1:?Usage: $0 <image> [tag]}"
TAG="${2:-}"

# Docker Hub's API wants the "library/" namespace for official images.
REPO="$IMAGE"
[[ "$IMAGE" != */* ]] && REPO="library/$IMAGE"

if [ -z "$TAG" ]; then
    echo "Fetching available tags for $IMAGE..."
    TAGS_JSON=$(curl -fsSL "https://hub.docker.com/v2/repositories/$REPO/tags?page_size=25&ordering=last_updated") \
        || { echo "Could not reach Docker Hub — check network." >&2; exit 1; }
    mapfile -t TAGS < <(echo "$TAGS_JSON" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    [ "${#TAGS[@]}" -gt 0 ] || { echo "No tags found for $REPO" >&2; exit 1; }

    echo ""
    echo "Recent tags for $IMAGE:"
    for i in "${!TAGS[@]}"; do
        printf "  %2d) %s\n" "$((i+1))" "${TAGS[$i]}"
    done
    echo ""
    read -rp "Pick a tag [1-${#TAGS[@]}]: " CHOICE
    [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#TAGS[@]}" ] \
        || { echo "Invalid choice." >&2; exit 1; }
    TAG="${TAGS[$((CHOICE-1))]}"
fi

REF="$IMAGE:$TAG"
SAFE_NAME="$(echo "$REPO" | tr '/' '_')_${TAG}.tar"

echo "Pulling $REF..."
docker pull "$REF"

mkdir -p "$DIST_DIR"
echo "Saving to takserver-dist/$SAFE_NAME..."
docker save -o "$DIST_DIR/$SAFE_NAME" "$REF"

echo ""
echo "Done: takserver-dist/$SAFE_NAME"
echo "Update the corresponding FROM/image line to '$REF' if the tag changed."
