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

# Patch 3: Add facade class aliases so digitalpy can register FTS components
# digitalpy expects PascalCase(dir_name) but FTS classes are named e.g. FTSCoreFacade
RUN python3 - <<'EOF'
import re, os

def to_pascal(s):
    return ''.join(w.capitalize() for w in s.replace('-','_').split('_'))

count = 0
for dirpath, _, filenames in os.walk('/home/freetak/FreeTAKServer'):
    for fname in filenames:
        if not fname.endswith('_facade.py'):
            continue
        fpath = os.path.join(dirpath, fname)
        expected = to_pascal(os.path.basename(dirpath))
        with open(fpath) as f:
            content = f.read()
        classes = re.findall(r'^class (\w+)', content, re.MULTILINE)
        if not classes or expected in classes:
            continue
        facade_cls = next((c for c in classes if c.endswith('Facade')), classes[0])
        # Subclass wrapper: digitalpy passes 4 constructor args but FTS facades take none
        wrapper = (f'\nclass {expected}({facade_cls}):\n'
                   f'    def __init__(self, *args, **kwargs):\n'
                   f'        {facade_cls}.__init__(self)\n')
        with open(fpath, 'a') as f:
            f.write(wrapper)
        print(f'  {os.path.basename(dirpath)}: created {expected}({facade_cls}) wrapper')
        count += 1
print(f'Added {count} facade wrappers')
EOF

# Patch 4: Wrap put_mission in try/except — unhandled exceptions crash the FTS process
RUN python3 - <<'PYEOF'
import re

def patch_put_mission(path):
    try:
        with open(path) as f:
            src = f.read()
    except FileNotFoundError:
        print(f'Skipping (not found): {path}')
        return
    if 'put_mission_patched' in src:
        print(f'Already patched: {path}')
        return
    lines = src.splitlines(keepends=True)
    out = []
    i = 0
    while i < len(lines):
        m = re.match(r'^(\s*)def put_mission\(', lines[i])
        if m:
            fn_ind = m.group(1)
            body_ind = fn_ind + '    '
            out.append(lines[i]); i += 1
            body = []
            while i < len(lines) and (not lines[i].strip() or lines[i].startswith(body_ind)):
                body.append(lines[i]); i += 1
            out.append(body_ind + 'try:  # put_mission_patched\n')
            for bl in body:
                out.append('    ' + bl if bl.strip() else bl)
            out.append(body_ind + 'except Exception as _e:\n')
            out.append(body_ind + '    import traceback; traceback.print_exc()\n')
            out.append(body_ind + '    return str(_e), 500\n')
        else:
            out.append(lines[i]); i += 1
    with open(path, 'w') as f:
        f.writelines(out)
    print(f'Patched: {path}')

for svc in ['http_tak_api_service', 'https_tak_api_service']:
    patch_put_mission(f'/home/freetak/FreeTAKServer/services/{svc}/blueprints/mission_blueprint.py')
PYEOF

# Patch 5: Fix enterprise sync upload — iTAK sends 'uid' not 'hash' in the URL,
# so objectuid was always None and metadata.hash was null in the response,
# causing iTAK to retry 3× and show "unknown error" despite data being stored.
RUN python3 - <<'EOF'
paths = [
    '/home/freetak/FreeTAKServer/services/http_tak_api_service/blueprints/enterprise_sync_blueprint.py',
    '/home/freetak/FreeTAKServer/services/https_tak_api_service/blueprints/enterprise_sync_blueprint.py',
]
for path in paths:
    try:
        with open(path) as f: src = f.read()
        src = src.replace(
            '"objectuid": request.args.get(\'hash\'), "tool"',
            '"objectuid": request.args.get(\'hash\') or request.args.get(\'uid\'), "tool"'
        )
        # Always return SHA-256 of content — metadata.hash is a UUID, not a hash
        src = src.replace(
            '"Hash": metadata.hash,',
            '"Hash": __import__("hashlib").sha256(data).hexdigest(),'
        )
        with open(path, 'w') as f: f.write(src)
        print(f'Patched: {path}')
    except Exception as e:
        print(f'Error: {path}: {e}')
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
