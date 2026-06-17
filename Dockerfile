# syntax=docker/dockerfile:1
ARG TEMURIN_VERSION="17"
ARG TAK_RELEASE="5.7-RELEASE-43"

# ── Stage 1: extract TAK distribution ZIP ────────────────────────────────────
FROM pvarki/tak-server-dist:${TAK_RELEASE} AS tak-files
RUN mv /zips/takserver-docker-*.zip /tmp/takserver.zip

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
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh \
       -o /usr/bin/wait-for-it.sh \
    && chmod a+x /usr/bin/wait-for-it.sh

COPY --from=hairyhenderson/gomplate:stable /gomplate /bin/gomplate

SHELL ["/bin/bash", "-lc"]

# ── Stage 3: install TAK Server + project scripts/templates ──────────────────
FROM deps AS install

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY --from=tak-files /tmp/takserver.zip /tmp/takserver.zip
RUN cd /tmp \
    && unzip takserver.zip \
    && rm takserver.zip \
    && DISTDIR=$(echo takserver-docker-*) \
    && mv "$DISTDIR/tak" /opt/tak

COPY scripts /opt/scripts
COPY templates /opt/templates

# ── Stage 4: runtime image ───────────────────────────────────────────────────
FROM install AS run
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
