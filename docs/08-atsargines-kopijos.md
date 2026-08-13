# 08 — Atsarginės kopijos

## Kas kopijuojama

```bash
./backup.sh [output-dir]   # numatyta: backups/<laikas>/
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
./restore.sh <backup-dir>
```

**Destruktyvu.** Perrašo esamą admin DB, TAK CoT DB, sertifikatus/paketus, papildinius ir žemėlapius atsarginės kopijos duomenimis. Reikalauja įvesti `restore`, kad patvirtintumėte.

> Prieš atkūrimą įsitikinkite, kad `<backup-dir>` yra teisingas — skriptas patikrina tik `admin_db.sql` egzistavimą kaip minimalų validumo ženklą, ne pilną turinio nuoseklumą.

## Kada daryti atsarginę kopiją

- Prieš `./update.sh` produkciniame diegime.
- Prieš `TAKSERVER_CERT_PASS`/`CA_PASS` keitimą (žr. [05-sertifikatai-ir-saugumas.md](05-sertifikatai-ir-saugumas.md)) — po tomo išvalymo atkurti nebus iš ko, jei kopijos nėra.
- Reguliariai, jei diegimas naudojamas produkcijoje — šis repo nesiūlo automatinio suplanuoto (`cron`) kopijavimo, tai reikia sukonfigūruoti pačiam.
