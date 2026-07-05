# Wraps your tak.gov-downloaded TAK Server zip in a minimal image so other
# machines can `docker pull` it instead of you scp-ing a 600MB file by hand —
# same pattern pvarki/tak-server-dist used, just hosted on your own GHCR.
# Build/push with scripts/publish_tak_dist.sh — do not build this by hand.
FROM scratch
COPY takserver-docker-*.zip /zips/
