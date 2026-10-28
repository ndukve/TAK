# 09 — Problemų sprendimas

## Pirmas žingsnis visada

```bash
./scripts/health.sh
```

Patikrina, ar veikiantys atvaizdai atitinka dabartinį `git` commit (Docker sluoksnio talpyklos problemos simptomas — kodas pasikeitė diske, bet konteineris vis dar veikia su senu build'u), ir paleidžia paketo generatoriaus self-test'ą. Priverstinai perstato (`--no-cache`), jei randa neatitikimą.

## Dažni simptomai

| Simptomas | Priežastis | Sprendimas |
|---|---|---|
| Kliento paketo atsisiuntimas `:8888` neveikia | Portas pasenęs dokumentacijoje, faktiškai neatvertas | Naudoti admin panelę (`:1414`, Packages → Download) arba `./scripts/admin_fallback.sh` — žr. [06-tinklas-ir-prieiga.md](06-tinklas-ir-prieiga.md) |
| Po `TAKSERVER_CERT_PASS`/`CA_PASS` keitimo klientai/servisai nebesijungia | Senas JKS tome, naujas slaptažodis env faile — nesutampa | Reikia tomo išvalymo ir sertifikatų regeneravimo, žr. [05-sertifikatai-ir-saugumas.md](05-sertifikatai-ir-saugumas.md) — **prieš tai** padaryti atsarginę kopiją |
| Konteinerio veiksmas (pvz. sertifikato generavimas per admin panelę) grąžina `No such container: <vardas>` | `docker_socket_proxy` neranda tikslinio konteinerio — arba jis neveikia, arba tai izoliuota dev aplinka be pilno TAK steko | `make status` patikrinti, ar servisas veikia; pilname diegime patikrinti `docker compose ps` |
| Kodo pakeitimai diske, bet konteineryje senas elgesys | Docker sluoksnio talpyklos (layer cache) problema | `./scripts/health.sh` (self-heal aptinka ir taiso automatiškai) |
| WebUI visiškai nepasiekiama | Tinklo/portų problema arba `admin`/`admin_proxy` servisas nulūžęs | `make status`, `make logs`; jei reikia tik peržiūrėti/atsisiųsti paketus — `./scripts/admin_fallback.sh` (terminalo, tik skaitymui) |
| `update.sh` sustoja po build'o | Self-test nepavyko | `update.sh` automatiškai iškviečia `health.sh`; jei ir tai nepadeda, žr. build logus rankiniu `docker compose build --progress plain` |
| Atvaizdas pastatytas (`docker compose build ...`), bet pakeitimas neveikia | Vien `build` neperkuria veikiančių konteinerių — jie ir toliau veikia su senu atvaizdu, kol kažkas jų nepaleidžia iš naujo | Naudoti `make build` (automatiškai iškviečia `make up`) vietoj tiesioginio `docker compose build`; arba po rankinio build'o visada paleisti `docker compose up -d` |
| iTAK rodo „Invalid Truststore“; ATAK/WinTAK rodo „Please re-import your trust store certificate“ ir nepasiekia serverio | `makeCert.sh` eksportuoja legacy PKCS#12 TAK Server Java reikmėms. ATAK/WinTAK paketai kliento ir truststore failus perkoduoja. iTAK šaka abu failus kopijavo nepakeistus; pateiktame iTAK archyve PKCS#12 MAC naudoja SHA-1, o ATAK/WinTAK archyvuose — SHA-256. ATAK archyvas jau naudoja modernų formatą, tad vien šis patikrinimas nepaaiškina likusios klaidos | iTAK pataisyta — `make_pkg_zip.sh` dabar perkoduoja ir abu iTAK failus, išlaikydamas plokščią ZIP struktūrą. Perkurkite ir iš naujo paleiskite `takserver_config`, WebUI atnaujinkite iTAK paketą, įrenginyje pašalinkite seną serverio / sertifikato įrašą ir importuokite naują paketą. Jei ATAK klaida lieka, pašalinkite atkurtus senus įrašus ir patikrinkite, ar paketas sugeneruotas atnaujintu image; toliau reikia patikrinti CA turinį / slaptažodį, neatskleidžiant privačių raktų |
| Paspaudus paketą ATAK „Local SD" importe nieko nevyksta (jokio pranešimo, jokios klaidos, varnelė+OK taip pat nepadeda) | Pačios ATAK fono failų stebėjimo mechanizmas (turi pastebėti importuotą failą ir jį apdoroti) yra žinomai nepatikimas kai kuriose Android versijose/įrenginiuose — failas tiesiog lieka neapdorotas | Pirmiausia priverstinai uždaryti ir iš naujo paleisti ATAK (paleidimo metu atliekama pilna peržiūra, kuri gali pastebėti praleistą failą). Jei nepadeda — išvalyti ATAK programėlės podėlį **ir saugyklos duomenis** (Android Nustatymai → Programėlės → ATAK → Saugykla) — praktikoje tai patikimai išsprendė užstrigusį importą |
| Didelio žemėlapio failo (kelių GB `.mbtiles`) atsisiuntimo mygtukas nieko nedaro / atrodo užstrigęs | Atsisiuntimas laikė visą failą naršyklės Blob objekte prieš išsaugant — užstringa arba atrodo pakibęs prie kelių GB failų | Ištaisyta — žemėlapių atsisiuntimai dabar srautu per vienkartinį bilietą ir tiesioginį naršyklės atsisiuntimą vietoj Blob. Įsitikinti, kad `admin` konteineris perstatytas/perdiegtas (žr. eilutę apie `make build` aukščiau) |
| Live Map žemėlapio plytelėse rodomas didelis „API KEY REQUIRED" ženklas vietoj žemėlapio | Senas CARTO plytelių tiekėjas dabar reikalauja mokamo API rakto | Ištaisyta — plytelės perjungtos į nemokamą OpenStreetMap. Jei vis dar matoma — perstatyti/perdiegti `admin` |
| Live Map plytelėse rodoma „Access blocked — App is not following the tile usage policy" (403) | Tiesioginis OpenStreetMap plytelių atsisiuntimas iš naršyklės negali nustatyti tikro User-Agent ir neturi podėlio — abu reikalauja OSM plytelių naudojimo politika, todėl intensyvus/anoniminis naudojimas užblokuojamas | Ištaisyta — plytelės dabar eina per `/api/live-map/tiles` (admin backend), kuris nustato tikrą User-Agent ir talpina kiekvieną plytelę į diską (`/tmp/tile-cache`), todėl pakartotiniai peržiūrėjimai daugiau nebekreipiasi į OpenStreetMap. Jei vis dar matoma — perstatyti/perdiegti `admin` |
| ATAK savaime nerodo kitų naudotojų žymeklių ar EFDI sensorių pėdsakų — WinTAK visada rodo, o ATAK žymeklis atsiranda tik po rankinio „Send To" konkrečiam kontaktui | Įrenginio sertifikatas nėra (arba nebėra) bendros maršruto grupės `TAK-USERS` narys — TAK Server automatiškai transliuoja CoT tik tarp tos pačios grupės narių. Rankinis „Send To" grupės maršrutizavimą apeina, todėl jis vis tiek veikia. Serverio gyvos grupės narystės talpykla taip pat gali „užstrigti" net tinkamai sukonfigūruotam įrenginiui | Paleisti `./scripts/users.sh repair-groups` — priskirs visus supakuotus klientus grupei `TAK-USERS`. Jei žymekliai vis tiek nerodomi, tikėtina „užstrigo" grupės narystės talpykla — pilnas perkrovimas ją išvalo: `docker compose down && docker compose up -d` (serveris trumpam atsijungs) |
| Dronų valdymo programėlės (GCS) rodoma gyva drono pozicija niekada neatsiranda ATAK „UAS Tool" įrankyje | ATAK „UAS Tool" droną aptinka tik iš MAVLink telemetrijos, atsiunčiamos jam per UDP — GCS programėlė ten jos nesiunčia, kol nesukonfigūruota | GCS programėlėje įjungti MAVLink persiuntimą (QGroundControl pagrindu sukurtose programėlėse: Settings → General → MAVLink → Forward Mavlink) į UDP portą 14550, nukreiptą į ATAK įrenginį — `127.0.0.1`, jei GCS programėlė ir ATAK veikia tame pačiame įrenginyje, kitu atveju — įrenginio LAN arba NetBird IP. ATAK „UAS Tool" tada droną parodo automatiškai, importuoti nereikia |
| Plugins sąraše ATAK, WinTAK ir iTAK paketai sumaišyti kartu, iš pirmo žvilgsnio negalima atskirti, kuris kuriam | Sena sąsaja (ištaisyta): plugin įkėlimai neturėjo app-type ar versijos metaduomenų | Įkėlimas dabar klausia tikslinės programos (ATAK/WinTAK/iTAK/Other) ir versijos; Packages → Plugins sąrašas automatiškai grupuoja ir rikiuoja pagal app-type |
| TAK diegimo programa: „NetBird — FAILED … DeadlineExceeded“ LAN VM | Savo NetBird serverio viešas vardas iš LAN vidaus neatsako (nėra hairpin NAT); atsako tik jo LAN adresas | VM `/etc/hosts` pridėkite serverio LAN adresą tam vardui, tada valdymo adresą įveskite **be prievado** (pavyzdžiui, `https://nbio.fairytail.eu`, ne `:33073`); paruošimo raktą įvedate patys ir naudojate vieną kartą. Išsamiau – EFDI-Core `docs/11-dazniausios-problemos.md` |
| Admin panelė neatsidaro adresu `https://tak.efdi.ltu` | Panelė veikia 1414 ir 443 prievaduose, todėl adresas su kitu prievadu nieko neranda | Atidarykite `https://tak.efdi.ltu` (443) arba `https://tak.efdi.ltu:1414`; naršyklė turi būti NetBird tinkle, kad vardas išsispręstų, ir įspės, kol nepatikėsite TAK CA |
| `restore.sh` į naują įdiegimą: `admin_permissions` baigiasi 1 („maybe wrong password“) | Atkurti sertifikatai užšifruoti senojo `takserver.env` slaptažodžiais | Iš kopijos `takserver.env` į naująjį nukopijuokite `CA_PASS`, `ADMIN_CERT_PASS`, `TAKSERVER_CERT_PASS` ir `ADMIN_SECRET_KEY`, tada `docker compose --env-file takserver.env up -d --force-recreate` (08 dok.) |

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
