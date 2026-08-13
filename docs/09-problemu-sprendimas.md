# 09 — Problemų sprendimas

## Pirmas žingsnis visada

```bash
./health.sh
```

Patikrina, ar veikiantys atvaizdai atitinka dabartinį `git` commit (Docker sluoksnio talpyklos problemos simptomas — kodas pasikeitė diske, bet konteineris vis dar veikia su senu build'u), ir paleidžia paketo generatoriaus self-test'ą. Priverstinai perstato (`--no-cache`), jei randa neatitikimą.

## Dažni simptomai

| Simptomas | Priežastis | Sprendimas |
|---|---|---|
| Kliento paketo atsisiuntimas `:8888` neveikia | Portas pasenęs dokumentacijoje, faktiškai neatvertas | Naudoti admin panelę (`:8889`, Packages → Download) arba `./admin_fallback.sh` — žr. [06-tinklas-ir-prieiga.md](06-tinklas-ir-prieiga.md) |
| Po `TAKSERVER_CERT_PASS`/`CA_PASS` keitimo klientai/servisai nebesijungia | Senas JKS tome, naujas slaptažodis env faile — nesutampa | Reikia tomo išvalymo ir sertifikatų regeneravimo, žr. [05-sertifikatai-ir-saugumas.md](05-sertifikatai-ir-saugumas.md) — **prieš tai** padaryti atsarginę kopiją |
| Konteinerio veiksmas (pvz. sertifikato generavimas per admin panelę) grąžina `No such container: <vardas>` | `docker_socket_proxy` neranda tikslinio konteinerio — arba jis neveikia, arba tai izoliuota dev aplinka be pilno TAK steko | `make status` patikrinti, ar servisas veikia; pilname diegime patikrinti `docker compose ps` |
| Kodo pakeitimai diske, bet konteineryje senas elgesys | Docker sluoksnio talpyklos (layer cache) problema | `./health.sh` (self-heal aptinka ir taiso automatiškai) |
| WebUI visiškai nepasiekiama | Tinklo/portų problema arba `admin`/`admin_proxy` servisas nulūžęs | `make status`, `make logs`; jei reikia tik peržiūrėti/atsisiųsti paketus — `./admin_fallback.sh` (terminalo, tik skaitymui) |
| `update.sh` sustoja po build'o | Self-test nepavyko | `update.sh` automatiškai iškviečia `health.sh`; jei ir tai nepadeda, žr. build logus rankiniu `docker compose build --progress plain` |

## Logai

```bash
make logs        # visi servisai
make logs-db     # tik takdb
make status      # servisų būsena + klausomi portai
```

## Kai niekas nepadeda

1. Patikrinti, ar `takserver.env` egzistuoja ir yra pilnas (palyginti su `takserver.env.example`).
2. Patikrinti Docker Engine būseną (`docker info`).
3. Jei diegimas kritinis ir laikas spaudžia — atkurti iš paskutinės atsarginės kopijos ([08-atsargines-kopijos.md](08-atsargines-kopijos.md)), o ne bandyti taisyti gyvą sistemą toliau.
