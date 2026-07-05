# syntax=docker/dockerfile:1

# ── Stage 1: base system with all runtime deps ────────────────────────────────
# Every base image below is pulled through the local registry mirror (see the
# `registry` service in docker-compose.yml), pinned by exact digest so builds
# are reproducible and don't silently drift when upstream retags :stable/:alpine/etc.
FROM localhost:5000/library/eclipse-temurin@sha256:0386aaf49d6756b4856119f8e037f40cc865c7c8fbdda7c81733cc806f462daf AS deps
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

COPY --from=localhost:5000/hairyhenderson/gomplate@sha256:23914375b491cbfb6620911200ff5ed31af200cd66484c833496fca1dfc97e74 /gomplate /bin/gomplate

SHELL ["/bin/bash", "-lc"]

# ── Stage 2: install TAK Server + project scripts/templates ──────────────────
FROM deps AS install

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# takserver-dist/ holds your own tak.gov-downloaded release ZIP (gitignored —
# licensed binary, not redistributed via git). See .gitignore for the rule.
COPY takserver-dist/takserver-docker-*.zip /tmp/takserver.zip
RUN cd /tmp \
    && unzip takserver.zip \
    && rm takserver.zip \
    && DISTDIR=$(echo takserver-docker-*) \
    && mv "$DISTDIR/tak" /opt/tak

COPY scripts /opt/scripts
COPY templates /opt/templates

# ── Stage 3: runtime image ───────────────────────────────────────────────────
FROM install AS run
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.revision="$GIT_COMMIT"
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
