# 04 — Kasdieniai darbai

Dauguma šių veiksmų atliekami arba per **admin panelę** (paprasčiau, rekomenduojama), arba per **`make`** komandas terminale (kai nėra prieigos prie WebUI arba reikia automatizuoti).

## Naujas naudotojas

**Admin panelėje:** Users → New User → callsign + kliento tipas (ATAK/WinTAK/iTAK/Service).

**Terminale** — sugeneruoja sertifikatą, paketą IR autorizuoja serveryje vienu žingsniu:

```bash
make add-user USERNAME=alice-iTAK   # privaloma baigtis -ATAK / -WinTAK / -iTAK
```

Granulesnis valdymas (jei reikia atskirti žingsnius):

```bash
make gen-device-cert USERNAME=alice-iTAK   # tik sertifikatas (.p12), dar neautorizuotas
make make-package USERNAME=alice-iTAK      # paketo .zip iš esamo sertifikato
make gen-cert USERNAME=alice-iTAK          # abu aukščiau esantys, bet dar neautorizuotas
make enable-user USERNAME=alice-iTAK       # autorizuoja jau sugeneruotą sertifikatą
```

Paketas atsisiunčiamas per `http://<serveris>:8888/<username>.zip` arba admin panelėje (Packages → Download).

## Naudotojų sąrašas

```bash
make list-packages
```

Arba admin panelėje: Packages.

## Papildiniai (plugins)

**Kliento papildinys** (APK, atsisiunčiamas per klientą):

```bash
make add-plugin APK=/path/to/plugin.apk
make list-plugins
```

**Serverio papildinys** (JAR, keičia `takserver_pluginmanager` elgesį):

```bash
make install-plugin JAR=/path/to/plugin.jar
```

Arba admin panelėje: Plugins.

## Žemėlapiai (basemaps)

Admin panelėje: Basemaps — ESRI/Google kompoziciniai bazlapiai, aplinkos overlay'ai (NOAA radaras, NASA IMERG, GOES), TAK distribucija prisijungusiems EUD (End User Device).

## Mašininės integracijos (serviso paskyros)

Sertifikatas mašininei integracijai (pvz. EFDI moon-pod), be TAK kliento paketo:

```bash
make add-service NAME=efdi-pod
```

## Būsena ir logai

```bash
make status      # servisai + klausomi portai
make logs         # visų servisų logai (sekimo režimu)
make logs-db      # tik takdb logai
make shell        # bash į takserver_config konteinerį
```

Admin panelėje: Dashboard (bendra būsena), Logs (superadmin).

## Ką daryti, jei WebUI nepasiekiama

`./admin_fallback.sh` — terminalo interaktyvus meniu paketų/žemėlapių peržiūrai ir atsisiuntimui. Tik skaitymui (be kūrimo/naikinimo), reikalauja SSH prieigos prie serverio. Žr. [09-problemu-sprendimas.md](09-problemu-sprendimas.md).
