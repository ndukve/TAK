# 02 — Repo Structure

```
TAK/
├── Dockerfile                  TAK Server image build
├── docker-compose.yml          Production container stack
├── docker-compose.host.yml     Alternative without Docker socket proxy isolation
├── install.sh                  Interactive installer (Docker + VPN + config)
├── install-offline.sh          Offline install (pre-fetched images)
├── update.sh                   git pull + rebuild + self-test (see doc 10)
├── health.sh                   Self-heal + self-test for a running deployment (see doc 09)
├── backup.sh / restore.sh      Backups (see doc 08)
├── users.sh                    User/package management (create, purge, get)
├── admin_fallback.sh           Terminal "break-glass" access when the WebUI is unavailable
├── Makefile                    Short commands wrapping all of the above
├── takserver.env.example       Config template (copied to takserver.env)
├── scripts/
│   ├── firstrun.sh              PKI bootstrap + DB schema init
│   ├── start-tak.sh             Container entrypoint
│   ├── make_client_zip.sh       Client data package assembly
│   ├── gen_client_cert.sh       Client certificate generation
│   ├── enable_user.sh           Registers a cert with UserManager
│   ├── generate_service_cert.sh PEM cert for machine integrations (e.g. EFDI)
│   └── _spinner.sh / _tui.sh / _selftest.sh   Shared installer/script helpers
├── templates/
│   ├── CoreConfig.tpl           TAK server config (gomplate template)
│   └── missionpkg(-itak)/       Client data package templates
├── admin/
│   ├── api/                     FastAPI backend (auth, users, packages, replay, live_map, oidc, ...)
│   ├── ui/                      React + Vite + Tailwind frontend
│   ├── nginx/                   admin_proxy (TLS reverse proxy) config
│   └── tests/                   Backend tests
└── docs/
    ├── INSTALL.md / DIEGIMAS.md Full install guide (EN/LT)
    ├── 00–11 …                  This operator manual
    └── branding/                Default branding assets (logo placeholder)
```

## Where to look

| Need to... | Look at |
|---|---|
| Change TAK server configuration | `templates/CoreConfig.tpl` |
| Add/change an admin panel endpoint | `admin/api/*.py` |
| Change the admin panel UI | `admin/ui/src/routes/*.tsx` |
| Change the install flow | `install.sh` |
| Add a new `make` command | `Makefile` |
| Understand an env variable | [11-technical-reference.md](11-technical-reference.md) or the comments in `takserver.env.example` |

`admin/.venv`, `admin/ui/node_modules`, `admin/ui/dist`, `*/__pycache__`, `.ruff_cache`, `.pytest_cache` — generated/local, not git-tracked (see `.gitignore`).
