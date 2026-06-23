# Diegimo instrukcija

Šis vadovas aprašo TAK serverio diegimą naujame Ubuntu 22.04 kompiuteryje. Docker ar TAK patirtis nereikalinga.

---

## Prieš pradedant

Jums reikės:

- Kompiuterio su **Ubuntu 22.04** (serverio leidimas, minimalus diegimas) ir interneto ryšiu
- Nemokamos **NetBird paskyros** [app.netbird.io](https://app.netbird.io) — ji sukuria šifruotą tunelį tarp serverio ir jūsų įrenginių
- **NetBird programėlės** kiekviename įrenginyje, kuris jungiasi prie TAK
- TAK kliento programėlės: **iTAK** (iOS), **ATAK** (Android) arba **WinTAK** (Windows)

Minimalūs serverio reikalavimai: 4 CPU branduoliai · 6 GB RAM · 40 GB disko vietos

---

## 1 žingsnis — Sukurti NetBird setup raktą

Setup raktas leidžia įrenginiams prisijungti prie jūsų privataus NetBird tinklo.

1. Prisijunkite prie [app.netbird.io](https://app.netbird.io)
2. Kairėje juostoje pasirinkite **Setup Keys**
3. Spustelėkite **Create setup key**, suteikite pavadinimą (pvz. `TAK`), spustelėkite **Create**
4. Nukopijuokite raktą — jo prireiks kitame žingsnyje

---

## 2 žingsnis — Paleisti diegimo skriptą

Ubuntu kompiuteryje atidarykite terminalą ir paleiskite:

```bash
curl -fsSL https://raw.githubusercontent.com/ndukve/TAK/main/install.sh | bash
```

Kai paklaus apie tinklą, pasirinkite **1 parinktį (Install & connect NetBird)** ir įklijuokite setup raktą. Skriptas automatiškai:

- Įdiegs Docker Engine
- Įdiegs ir prijungs NetBird naudodamas jūsų setup raktą
- Aptiks NetBird IP adresą (`wt0` sąsaja) ir naudos jį kaip serverio adresą
- Paklaus sertifikatų metaduomenų (šalis, valstija, miestas, organizacija — numatytosios reikšmės tinka testavimui)
- Automatiškai sugeneruos visus slaptažodžius
- Sukurs TAK serverio Docker atvaizdą ir paleis visas paslaugas

Diegimas trunka apie 5–10 minučių. Kai pasirodys suvestinės ekranas, serveris veikia.

---

## 3 žingsnis — Prijungti įrenginį prie NetBird

Kiekvienas įrenginys, kuris jungiasi prie TAK, turi būti tame pačiame NetBird tinkle.

1. Įdiekite NetBird programėlę:
   - iOS: [App Store](https://apps.apple.com/app/netbird/id6469329339)
   - Android: [Google Play](https://play.google.com/store/apps/details?id=io.netbird.client)
2. Atidarykite programėlę → **Connect with setup key** → įklijuokite raktą iš 1 žingsnio
3. Palaukite, kol būsena taps **Connected**

---

## 4 žingsnis — Sugeneruoti vartotojo paketą

Serveryje paleiskite:

```bash
cd ~/tak-server
./generate_user.sh JusuŠaukinis
```

Ši komanda sugeneruoja duomenų paketą su kliento sertifikatu ir serverio ryšio konfigūracija. Įrenginio naršyklėje atidarykite:

```
http://<SERVERIO_NETBIRD_IP>:8888/JusuŠaukinis.zip
```

Serverio NetBird IP rodomas diegimo pabaigoje. Taip pat galite jį gauti komanda:

```bash
ip addr show wt0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
```

---

## 5 žingsnis — Importuoti paketą į TAK klientą

Atsisiųskite `.zip` failą ir importuokite:

**iTAK (iOS)**
Settings → Network → Servers → **+** → Upload Server Package → pasirinkite `.zip`

**ATAK (Android)**
Hamburger meniu → Settings → Network Preferences → TAK Servers → **+** → Import from file → pasirinkite `.zip`

**WinTAK (Windows)**
Settings → Network Preferences → Server Connections → **+** → Import → pasirinkite `.zip`

Serverio įrašas atsiras automatiškai. Paspauskite **Connect**.

---

## Kliento papildiniai (plugins)

ATAK papildiniai — tai APK failai, diegiami Android įrenginiuose, o ne serveryje. TAK serveris automatiškai palaiko visus standartinius papildinius per savo vidinius API.

### Papildinių įkėlimas į serverį platinimui

Nukopijuokite APK failus į serverį, kad komandos įrenginiai galėtų juos atsisiųsti adresu `http://<serveris>:8888/plugins/`:

```bash
cd ~/tak-server

# Įkelkite kiekvieną papildinį
make add-plugin APK=/kelias/iki/ATAK-Plugin-datasync-4.0.4-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-uastool-13.0.0-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-icetak-2.0.2-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-hammer-1.2-...-release.apk

# Peržiūrėkite įkeltus papildinius
make list-plugins
```

Android įrenginyje atidarykite naršyklę, eikite į `http://<SERVERIO_NETBIRD_IP>:8888/plugins/` ir paspauskite ant kiekvieno failo, kad įdiegtumėte. Tada ATAK → **Settings → Manage Plugins → Install from file**.

---

### DataSync

**Paskirtis:** Sinchronizuoja misijas, žemėlapių sluoksnius, duomenų paketus ir failus tarp visų prijungtų ATAK įrenginių per TAK serverį.

**Serverio reikalavimai:** Jokie — Mission API jau veikia jūsų TAK serveryje adresu `https://<serveris>:8443/Marti/api/missions`. Papildomos konfigūracijos nereikia.

**Diegimas įrenginyje:**
1. Atsisiųskite DataSync APK iš `http://<serveris>:8888/plugins/`
2. ATAK → **Settings → Manage Plugins → Install from file** → pasirinkite APK
3. Iš naujo paleiskite ATAK, jei paprašoma
4. DataSync atsiranda ATAK įrankių juostoje (sinchronizavimo piktograma)

**Pirmas naudojimas:** DataSync serverio adresą nuskaito iš jūsų `.zip` duomenų paketo — papildomos konfigūracijos nereikia.

---

### UAS Tool

**Paskirtis:** Rodo dronų vaizdo įrašą kaip "picture-in-picture" ant ATAK žemėlapio ir vaizduoja UAV takelius iš jūsų MAVLink tilto atskirame valdymo skydelyje.

**Serverio reikalavimai:** Jokie — dronų takeliai perduodami per CoT srautą, kurį EFDI bridge jau siunčia.

**Diegimas:** Ta pati APK diegimo procedūra kaip DataSync.

**EFDI integracija:** Kai MAVLink bridge veikia, UAS Tool automatiškai rodo visus MAVLink prijungtus dronus kaip mėlynas UAV piktogramas žemėlapyje. Vaizdo srauto URL konfigūruojamas UAS Tool nustatymuose kiekvienam dronui atskirai.

---

### ICE Voice (iceTAK)

**Paskirtis:** Šifruotas "push-to-talk" balsas per TAK tinklą naudojant XMPP/ICE protokolą.

**Serverio reikalavimai:** Jokie — naudoja esamą TCP ryšį su TAK serveriu.

**Diegimas:** Ta pati APK diegimo procedūra.

---

### Hammer

**Paskirtis:** Struktūrizuotos taktinės ataskaitos — 9-linijinis MEDEVAC, CAS (artima oro parama), SALUTE, SPOT ataskaitos. Siunčia ataskaitas kaip CoT pranešimus, matomus visiems prijungtiems įrenginiams.

**Serverio reikalavimai:** Jokie.

**Diegimas:** Ta pati APK diegimo procedūra.

---

## Pakeitimų žurnalas

| Data | Pakeitimas |
|------|-----------|
| 2026-06-14 | Pradinis commit — šakota iš oficialaus efdi-moon-pod-main saugyklos |
| 2026-06-15 | Baziniai bridge adapteriai sujungti; saugyklos struktūra nustatyta; pridėtas README |
| 2026-06-16 | airplanes.live bridge: regioniniai ADS-B ir pasauliniai kariniai orlaiviai |
| 2026-06-16 | ICAO NOTAM bridge: aktyvių NOTAM priėmimas per ICAO Dataservices API |
| 2026-06-16 | FlightRadar24 bridge: FR24 komercinės transliacijos integracija |
| 2026-06-16 | Windy bridge: taškų orų prognozių API integracija |
| 2026-06-16 | Protocol Buffer aprašai naujiems takelio tipams (aircraft_track, ais_track, aprs_track, cat62_track) |
| 2026-06-17/18 | Kokybės gerinimai: bridge'ų stabilumas, sluoksnių dublikatų filtravimas, takelio suliejimo derinimas |
| 2026-06-18 | ASTERIX pilno dekodavimo projektavimo specifikacijos dokumentas |
| 2026-06-19/22 | Papildomi bridge ir sluoksnių gerinimai; Giraffe ASTERIX bridge užbaigtas |
| 2026-06-22 | dronuradaras.lt bridge: akustinių jutiklių tinklas ir drono aptikimo įvykiai |
| 2026-06-22 | CoT DETECTION sekcija su garso įrašo URL ATAK pastabų lauke |
| 2026-06-22 | Radaro vietos žymeklis: publikacija paleidimo metu + 60 s keepalive, kad ATAK neprarastų žymeklio |
| 2026-06-23 | Saugumo patikrinimas: pašalintas koduotas API raktas iš register_topics.sh; raktas perkeltas į `$EFDI_PORTAL_KEY` aplinkos kintamąjį |
| 2026-06-23 | Saugumas: asmeninis namespace UUID, el. paštas, IP ir pardavėjo identifikatorius pašalinti iš visų sekamų failų; bridge'ai skaito `PARTNER_NAMESPACE` iš aplinkos |
| 2026-06-23 | Saugumas: `compose/.env` ir `register_topics.sh` pridėti į `.gitignore` — kredencialai lieka tik lokaliai |
| 2026-06-23 | Saugumas: neriboto HTTP kūno skaitymas `rest-http/bridge.py` apribotas iki 10 MB |
| 2026-06-23 | Dokumentacijos atnaujinimas: INSTALL.md (anglų), DIEGIMAS.md (lietuvių), README.md perrašytas kaip architektūros apžvalga |
| 2026-06-23 | ASTERIX CAT-34 I034/120 dekoderis: radaras pats praneša WGS-84 poziciją iš gyvo srauto — rankinis koordinačių nustatymas nebereikalingas |
| 2026-06-23 | Mobiliojo radaro palaikymas: pozicija, greitis ir kursas gaunami iš nuoseklių I034/120 pranešimų; ATAK rodo judėjimo taką ant transporto priemonėje montuojamų radarų |

---

## Dažnos problemos

**Nepavyksta atsisiųsti paketo įrenginyje**
Patikrinkite, ar NetBird programėlė rodo **Connected**. Paketų serveris pasiekiamas tik per NetBird tinklą.

**Serveris matomas, bet neprisijungia**
Paketas gali būti sugeneruotas su netinkamu serverio IP. Ištrinkite paketą, sugeneruokite iš naujo su `./generate_user.sh` ir importuokite pakartotinai.

**Ryšys nutrūksta užgęsus ekranui**
Išjunkite energijos taupymo optimizaciją TAK programėlei.
- Android: Settings → Apps → ATAK → Battery → **Unrestricted**
- iOS: išjunkite **Low Power Mode** Settings → Battery
