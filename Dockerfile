# syntax=docker/dockerfile:1
# ============================================================
# FreeTAKServer + FreeTAKServer-UI  —  single container
# Bakes stability patches into the image at build time
# ============================================================

# Stage 1: pull UI packages from the official UI image
FROM ghcr.io/freetakteam/ui:latest AS ui-source

# Stage 2: build on patched FTS base
FROM ghcr.io/freetakteam/freetakserver:latest

USER root

# Patch 1: SSL connection timeout — default 0.01s causes every SSL handshake to fail
RUN sed -i 's/timeout=0.01/timeout=300/g' \
    /home/freetak/FreeTAKServer/services/ssl_cot_service/ssl_cot_service_main.py

# Patch 2: Receive connection constants — default drops after 4 iterations in 30s
RUN python3 - <<'EOF'
f = '/home/freetak/FreeTAKServer/core/configuration/ReceiveConnectionsConstants.py'
with open(f) as fh:
    c = fh.read()
c = c.replace('self.RECEIVECONNECTIONDATATIMEOUT = 30',  'self.RECEIVECONNECTIONDATATIMEOUT = 300')
c = c.replace('self.MAX_RECEPTION_ITERATIONS = 4',       'self.MAX_RECEPTION_ITERATIONS = 1000')
with open(f, 'w') as fh:
    fh.write(c)
print('Patched ReceiveConnectionsConstants.py')
EOF

# Install supervisor to run FTS + UI as separate processes in one container
RUN apt-get update && apt-get install -y --no-install-recommends supervisor \
    && rm -rf /var/lib/apt/lists/*

# Copy UI site-packages into an isolated staging area (NOT into freetak's .local —
# the UI uses SQLAlchemy 1.3.x while FTS requires 2.x; mixing them breaks both)
COPY --from=ui-source /home/freetak/.local/lib/python3.11/site-packages /tmp/ui-pkgs

# Build an isolated venv for the UI so its deps never touch FTS's deps
RUN python3 -m venv /home/freetak/ui-venv \
    && cp -a /tmp/ui-pkgs/. /home/freetak/ui-venv/lib/python3.11/site-packages/ \
    && rm -rf /tmp/ui-pkgs \
    && chown -R freetak:freetak /home/freetak/ui-venv

# Write ui-run.sh using the venv's Python directly — avoids HOME/user-site issues
# when supervisord switches from root to freetak
RUN printf '#!/bin/sh\nVENV_PY=/home/freetak/ui-venv/bin/python3\nSITE=$($VENV_PY -c "import site; print(site.getsitepackages()[0])")\nexec $VENV_PY "${SITE}/FreeTAKServer-UI/run.py"\n' \
    > /home/freetak/ui-run.sh \
    && chmod +x /home/freetak/ui-run.sh \
    && chown freetak:freetak /home/freetak/ui-run.sh

# Ensure FTS data directory exists with open permissions
# (the bind-mounted host dir must be 777 too; done by install.sh)
RUN mkdir -p /opt/fts && chmod -R 777 /opt/fts

# Package download server script
COPY scripts/serve_packages.py /home/freetak/scripts/serve_packages.py

# Supervisord config — manages fts, fts-ui, and pkg-server
COPY supervisord.conf /etc/supervisor/conf.d/fts-all.conf

# supervisord must run as root so it can setuid to freetak for child processes
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/fts-all.conf"]
