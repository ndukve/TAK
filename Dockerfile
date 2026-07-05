# syntax=docker/dockerfile:1

ARG TAK_RELEASE="5.7-RELEASE-43"
ARG TEMURIN_VERSION="17"

# ── Stage 1: fetch TAK distribution ZIP ───────────────────────────────────────
# Vendored locally via scripts/vendor_tak_zip.sh, same treatment as the other
# base images: load_vendored_images (see scripts/_vendor.sh) puts this in the
# local image cache before build, so this FROM resolves with zero network.
FROM tak-server-dist:${TAK_RELEASE} AS tak-files

# ── Stage 2: base system with all runtime deps ────────────────────────────────
FROM eclipse-temurin:${TEMURIN_VERSION}-noble AS deps
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    emacs-nox \
    net-tools \
    netcat-traditional \
    vim \
    nmon \
    python3-lxml \
    unzip \
    tini \
    curl \
    pwgen \
    zip \
    openssh-client \
    postgresql-client \
    jq \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY docker/wait-for-it.sh /usr/bin/wait-for-it.sh
RUN chmod a+x /usr/bin/wait-for-it.sh

COPY --from=hairyhenderson/gomplate:stable /gomplate /bin/gomplate

SHELL ["/bin/bash", "-lc"]

# ── Stage 3: install TAK Server + project scripts/templates ──────────────────
FROM deps AS install

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY --from=tak-files /zips/takserver-docker-*.zip /tmp/takserver.zip
RUN cd /tmp \
    && unzip takserver.zip \
    && rm takserver.zip \
    && DISTDIR=$(echo takserver-docker-*) \
    && mv "$DISTDIR/tak" /opt/tak

COPY scripts /opt/scripts
COPY templates /opt/templates

# ── Stage 4: runtime image ───────────────────────────────────────────────────
FROM install AS run
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.revision="$GIT_COMMIT"
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
