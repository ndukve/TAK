# 08 — Atsarginės kopijos

## Kas kopijuojama

```bash
./scripts/backup.sh [output-dir]   # numatyta: backups/<laikas>/
```

- `admin_db.sql` — admin panelės PostgreSQL duomenų bazės dump'as (`pg_dump`)
- `cot_db.sql` — TAK CoT duomenų bazės dump'as
- `takserver_data.tar.gz` — sertifikatai, paketai, `/opt/tak/data` turinys
- `tak_plugins.tar.gz` — serverio papildiniai
- `tak-maps.tar.gz` — žemėlapių šaltiniai (jei yra `packages/tak-maps/`)
- `takserver.env` — konfigūracijos kopija

Visi failai gauna `chmod 600` — juose yra slaptažodžiai ir sertifikatų raktai.

## Atkūrimas

```bash
./scripts/restore.sh <backup-dir>
```

**Destruktyvu.** Perrašo esamą admin DB, TAK CoT DB, sertifikatus/paketus, papildinius ir žemėlapius atsarginės kopijos duomenimis. Reikalauja įvesti `restore`, kad patvirtintumėte.

**Atkūrimas į naują įdiegimą:** `restore.sh` neatkuria `takserver.env`, tačiau atkurti sertifikatai užšifruoti senojo failo slaptažodžiais. Prieš atkurdami nukopijuokite `CA_PASS`, `ADMIN_CERT_PASS`, `TAKSERVER_CERT_PASS` ir `ADMIN_SECRET_KEY` iš kopijos `takserver.env` į naująjį (nauji `POSTGRES_*` slaptažodžiai lieka, nes nauja duomenų bazė turi savo roles). Jei šios keturios reikšmės skiriasi, skriptas dabar atsisako vykdyti, nieko neperrašęs. Po atkūrimo paleiskite `docker compose --env-file takserver.env up -d --force-recreate`, o ne `make up`.

> Prieš atkūrimą įsitikinkite, kad `<backup-dir>` yra teisingas — skriptas patikrina tik `admin_db.sql` egzistavimą kaip minimalų validumo ženklą, ne pilną turinio nuoseklumą.

## Kada daryti atsarginę kopiją

- Prieš `./scripts/update.sh` produkciniame diegime.
- Prieš `TAKSERVER_CERT_PASS`/`CA_PASS` keitimą (žr. [05-sertifikatai-ir-saugumas.md](05-sertifikatai-ir-saugumas.md)) — po tomo išvalymo atkurti nebus iš ko, jei kopijos nėra.
- Reguliariai, jei diegimas naudojamas produkcijoje — šis repo nesiūlo automatinio suplanuoto (`cron`) kopijavimo, tai reikia sukonfigūruoti pačiam.

## Kur laikomi duomenys (ne Docker viduje)

Viskas, kas turi išlikti po perdiegimo, laikoma serveryje, o ne Docker tomuose, kataloge `TAK_DATA_DIR` faile `takserver.env` (numatyta `/srv/tak-data`):

| Katalogas | Kas jame |
|---|---|
| `takserver_data` | CA ir jos raktas, serverio ir klientų sertifikatai, klientų paketai |
| `tak_plugins`, `tak_plugin_conf` | klientams teikiami papildiniai ir jų konfigūracija |
| `takdb_data` | PostgreSQL duomenys (CoT ir admin duomenų bazės) |

Atvaizdus, konteinerius ir `/var/lib/docker` galima ištrinti, perkurti ar prarasti neliečiant šių katalogų, o `install.sh` (Reinstall) ir `update.sh` jų niekada netrina. Serveris, kuris dar turi senus vardinius tomus, juos vieną kartą nukopijuoja į `TAK_DATA_DIR` per `update.sh` ar `install.sh`; seni tomai paliekami, kol patys juos pašalinsite, o failas `.migrated-<dalis>` neleidžia kopijavimo pakartoti. `TAK_DATA_DIR` negali būti `/var/lib/docker` viduje.

`TAK_DATA_DIR` laikykite atskirame diske arba tame, kurį apima VM atsarginė kopija. `backup.sh` šiuos katalogus archyvuoja kaip root, nes CA raktą gali skaityti tik TAK naudotojas.
