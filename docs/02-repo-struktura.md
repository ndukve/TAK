# 02 — Repo struktūra

```
TAK/
├── Dockerfile                  TAK Server atvaizdo (image) surinkimas
├── docker-compose.yml          Produkcinis konteinerių aprašas
├── docker-compose.host.yml     Alternatyva be Docker socket proxy izoliacijos
├── install.sh                  Interaktyvus diegėjas (Docker + VPN + konfigūracija)
├── install-offline.sh          Diegimas be interneto (iš anksto atsisiųsti atvaizdai)
├── update.sh                   git pull + rebuild + self-test (žr. 10 dok.)
├── health.sh                   Self-heal + self-test veikiančiam diegimui (žr. 09 dok.)
├── backup.sh / restore.sh      Atsarginės kopijos (žr. 08 dok.)
├── users.sh                    Naudotojų/paketų valdymas (create, purge, get)
├── admin_fallback.sh           Terminalo „break-glass“ prieiga, jei WebUI nepasiekiama
├── Makefile                    Trumpos komandos aplink visus aukščiau esančius skriptus
├── takserver.env.example       Konfigūracijos šablonas (kopijuojamas į takserver.env)
├── scripts/
│   ├── firstrun.sh              PKI bootstrap + DB schemos inicializacija
│   ├── start-tak.sh             Konteinerio paleidimo taškas (entrypoint)
│   ├── make_client_zip.sh       Kliento duomenų paketo surinkimas
│   ├── gen_client_cert.sh       Kliento sertifikato generavimas
│   ├── enable_user.sh           Sertifikato registravimas UserManager'yje
│   ├── generate_service_cert.sh PEM sertifikatas mašininėms integracijoms (pvz. EFDI)
│   └── _spinner.sh / _tui.sh / _selftest.sh   Bendri diegėjo/skriptų pagalbiniai moduliai
├── templates/
│   ├── CoreConfig.tpl           TAK serverio konfigūracija (gomplate šablonas)
│   └── missionpkg(-itak)/       Kliento duomenų paketo šablonai
├── admin/
│   ├── api/                     FastAPI backend (auth, users, packages, replay, live_map, oidc, ...)
│   ├── ui/                      React + Vite + Tailwind frontend
│   ├── nginx/                   admin_proxy (TLS reverse proxy) konfigūracija
│   └── tests/                   Backend testai
└── docs/
    ├── INSTALL.md / DIEGIMAS.md Pilnas diegimo vadovas (EN/LT)
    ├── 00–11 …                  Šis operatoriaus vadovas
    └── branding/                Numatytieji prekės ženklo ištekliai (logotipo placeholder)
```

## Kur ieškoti ko

| Reikia... | Žiūrėti |
|---|---|
| Pakeisti TAK serverio konfigūraciją | `templates/CoreConfig.tpl` |
| Pridėti/keisti admin panelės endpoint'ą | `admin/api/*.py` |
| Keisti admin panelės UI | `admin/ui/src/routes/*.tsx` |
| Keisti diegimo eigą | `install.sh` |
| Pridėti naują `make` komandą | `Makefile` |
| Suprasti env kintamąjį | [11-techninis-zinynas.md](11-techninis-zinynas.md) arba `takserver.env.example` komentarai |

`admin/.venv`, `admin/ui/node_modules`, `admin/ui/dist`, `*/__pycache__`, `.ruff_cache`, `.pytest_cache` — generuojami/lokalūs, negit'inami (žr. `.gitignore`).
