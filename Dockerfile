# syntax=docker/dockerfile:1

ARG TAK_RELEASE="5.7-RELEASE-43"
ARG TEMURIN_VERSION="17"
# Defaults to pvarki's public redistribution — anyone cloning this repo can
# build with zero setup, no gated tak.gov account needed up front. Override
# in takserver.env (TAK_DIST_IMAGE=tak-server-dist:5.7-RELEASE-43, built
# locally via scripts/refresh_vendor.sh tak from your own zip, or
# ghcr.io/<you>/tak-server-dist:<version> if you've published one) if you'd
# rather build from your own tak.gov download instead.
ARG TAK_DIST_IMAGE="pvarki/tak-server-dist:${TAK_RELEASE}"

# ── Stage 1: fetch TAK distribution ZIP ───────────────────────────────────────
FROM ${TAK_DIST_IMAGE} AS tak-files

# ── Stage 2: base system with all runtime deps ────────────────────────────────
FROM eclipse-temurin:${TEMURIN_VERSION}-noble AS deps
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    net-tools \
    netcat-traditional \
    vim \
    nmon \
    python3-minimal \
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

COPY scripts/gomplate.py /usr/bin/gomplate
RUN chmod a+x /usr/bin/gomplate

SHELL ["/bin/bash", "-lc"]

# ── Stage 3: extract TAK away from the eventual runtime image history ────────
FROM deps AS tak-extract
COPY --from=tak-files /zips/takserver-docker-*.zip /tmp/takserver.zip
RUN cd /tmp \
    && unzip takserver.zip \
    && rm takserver.zip \
    && DISTDIR=$(echo takserver-docker-*) \
    && mv "$DISTDIR/tak" /opt/tak

# ── Stage 4: install TAK Server + project scripts/templates ──────────────────
FROM deps AS install

# The TAK processes do not need host-level root.  Keep a stable numeric ID so
# named volumes can be migrated by the short-lived permissions service in
# docker-compose.yml and shared consistently by every TAK container.
COPY --from=tak-extract --chown=10000:10000 /opt/tak /opt/tak
COPY --chown=10000:10000 scripts /opt/scripts
COPY --chown=10000:10000 templates /opt/templates

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ── Stage 5: runtime image ───────────────────────────────────────────────────
FROM install AS run
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.revision="$GIT_COMMIT"
USER 10000:10000
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
