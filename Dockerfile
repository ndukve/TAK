# syntax=docker/dockerfile:1
# ============================================================
# FreeTAKServer Production Dockerfile
# Bakes all stability patches into the image at build time
# ============================================================

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

# Ensure FTS data directory exists with open permissions
# (the bind-mounted host dir must be 777 too; done by install.sh)
RUN mkdir -p /opt/fts && chmod -R 777 /opt/fts

USER freetak
