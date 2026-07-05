# Loads any pre-fetched base-image tarballs from takserver-dist/ into the
# local Docker image cache, so `docker compose build` can use them without
# hitting the network. Use scripts/vendor_image.sh to fetch/update one.
# Safe to call even if none exist yet — build then falls back to a normal
# registry pull for whatever wasn't vendored.
load_vendored_images() {
    local dir="${1:-takserver-dist}" f
    for f in "$dir"/*.tar; do
        [ -e "$f" ] || continue
        docker load -i "$f" >/dev/null
    done
}
