## Prieš pradedant

Jums reikės:

- Kompiuterio su **Ubuntu 22.04** (serverio leidimas, minimalus diegimas) ir interneto ryšiu
- TAK kliento programėlės: **iTAK** (iOS), **ATAK** (Android) arba **WinTAK** (Windows)

**Minimalūs serverio reikalavimai:** 4 CPU branduoliai · 8 GB RAM · 40 GB disko vietos

**Pasirinkite, kaip įrenginiai pasiekia serverį:**

| Situacija | Ką naudoti |
|---|---|
| Visi įrenginiai tame **pačiame tinkle (LAN arba Wi-Fi)** kaip serveris | Serverio vietinis IP — VPN nereikia |
| Įrenginiai jungiasi **nuotoliniu būdu** (kitas tinklas, internetas) | NetBird arba Tailscale tunelį |

---

## 1 žingsnis — Pasirinkti tinklo variantą

### A variantas — Vietinis tinklas (be VPN)

Jei telefonai, nešiojami kompiuteriai ir TAK serveris yra tame pačiame Wi-Fi arba LAN tinkle, VPN nereikia. Serverio vietinis IP (pvz. `192.168.1.50`) naudojamas kaip serverio adresas.

> **Priskirti statinį IP** serveriui (arba DHCP rezervaciją maršrutizatoriuje). Jei IP pasikeičia, esami duomenų paketai nustos veikti.

Pereikite prie 2 žingsnio. Diegimo metu pasirinksite **„Enter address manually"** ir įvesite serverio LAN IP.

### B variantas — Nuotolinis prisijungimas (NetBird)

Jei įrenginiai jungiasi iš kito tinklo, naudokite NetBird šifruotam tuneliui sukurti.

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

> **Diegimui reikalingos root teisės.** Jei nesate root, skriptas automatiškai paleis save su `sudo` ir paprašys slaptažodžio vieną kartą. Likęs diegimas vyksta automatiškai.

Kai paklaus apie tinklą, pasirinkite variantą pagal 1 žingsnį:

- **1 parinktis — Install & connect NetBird** → įklijuokite setup raktą (B variantas)
- **2 parinktis — Install & connect Tailscale** → įklijuokite Tailscale auth raktą
- **3 parinktis — Enter address manually** → įveskite serverio LAN IP (A variantas)

Skriptas automatiškai:

- Įdiegs Docker Engine
- Prisijungs prie pasirinkto tinklo (arba praleis, jei rankinis IP)
- Paklaus sertifikatų metaduomenų (šalis, valstija, miestas, organizacija — numatytosios reikšmės tinka testavimui)
- Automatiškai sugeneruos visus slaptažodžius
- Sukurs TAK serverio Docker atvaizdą ir paleis visas paslaugas

> Diegimas trunka apie 5–10 minučių. Kai pasirodys suvestinės ekranas, serveris veikia.

---

## 3 žingsnis — Prijungti įrenginį prie tinklo

**Jei pasirinkote A variantą (vietinis tinklas):** praleiskite šį žingsnį. Įrenginiai pasiekia serverį tiesiogiai per LAN/Wi-Fi.

**Jei pasirinkote B variantą (NetBird):** įdiekite NetBird programėlę kiekviename įrenginyje, kuris jungiasi prie TAK.

1. Įdiekite NetBird programėlę:
   - iOS: [App Store](https://apps.apple.com/app/netbird/id6469329339)
   - Android: [Google Play](https://play.google.com/store/apps/details?id=io.netbird.client)
2. Atidarykite programėlę → **Connect with setup key** → įklijuokite raktą iš 1 žingsnio
3. Palaukite, kol būsena taps **Connected**

---

## 4 žingsnis — Sugeneruoti vartotojo paketą

Kiekvienas vartotojas gauna duomenų paketą (`.zip`), kuriame yra:

| Failas | Paskirtis |
|---|---|
| `<šaukinys>.p12` | **Kliento sertifikatas** — įrenginio tapatybė serveriui (mTLS) |
| `truststore-root.p12` | **CA pasitikėjimo saugykla** — leidžia įrenginiui patikrinti serverio sertifikatą |
| `blueteam.pref` | Serverio adresas, prievadas ir sertifikatų nustatymai |

Abu sertifikatų failai būtini. Kliento sertifikatas autentifikuoja įrenginį serveriui; pasitikėjimo saugykla — serverį įrenginiui.

**Šaukinys privalo baigtis `-ATAK`, `-WinTAK` arba `-iTAK`** — pvz. `Alpha1-iTAK`. Tai ne kosmetika: iTAK importavimo funkcijai reikia kitokios zip failo struktūros (sertifikatų failai šaknyje), nei ATAK/WinTAK naudojamas Mission Package formatas (sudėti į `content/` aplanką). Priesaga nurodo, kurį formatą sukurti. Pasirinkus netinkamą kliento tipą, paketas importuosis tyliai, bet serverio įrašas neatsiras.

### Standartinis būdas (generuoti ir suteikti prieigą vienu žingsniu)

```bash
cd ~/tak-server
./generate_user.sh Alpha1-iTAK
```

Paleidus be argumento, paklaus šaukinio interaktyviai.

Tas pats per administravimo skydelį: **Users → New User** — įveskite šaukinį ir pasirinkite kliento tipą iš sąrašo; priesaga pridedama automatiškai.

### Atskiras būdas (paruošti iš anksto, prieigą suteikti vėliau)

Jei norite sugeneruoti paketus iš anksto, nesuteikiant prieigos iš karto — pvz., paruošiant rinkinius prieš operaciją — naudokite skriptus tiesiogiai:

```bash
docker compose exec -T -e CLIENT_CERT_NAME=Alpha1-iTAK takserver_config \
    bash /opt/scripts/gen_client_cert.sh

docker compose exec -T -e CLIENT_CERT_NAME=Alpha1-iTAK -e TAK_SERVER_ADDRESS=<SERVERIO_IP> takserver_config \
    bash /opt/scripts/make_pkg_zip.sh

# Suteikti prieigą, kai esate pasiruošę
docker compose exec -T -e USER_CERT_NAME=Alpha1-iTAK takserver_config \
    bash /opt/scripts/enable_user.sh
```

Kai paketas paruoštas, atsisiųskite jį iš administravimo skydelio adresu `https://<SERVERIO_IP>:8889` — skiltis **Packages**.

Vietoje `<SERVERIO_IP>` naudokite:
- **A variantas:** serverio LAN IP (pvz. `192.168.1.50`)
- **B variantas:** serverio NetBird IP — gaukite komanda:

```bash
ip addr show wt0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
```

Sugeneravus paketą per administravimo skydelį, tam žmogui automatiškai sukuriama (arba pakartotinai panaudojama) paskyra: naudotojo vardas — jo bazinis šaukinys (pvz. `Alpha1`, be priesagos), o slaptažodis parodomas vieną kartą jo sukūrimo metu. Perduokite tą slaptažodį naudotojui kitu kanalu, ir jis galės pats prisijungti prie administravimo skydelio iš savo telefono ar nešiojamo kompiuterio, matyti tik savo paketus ir juos atsisiųsti tiesiogiai — operatoriui nebereikės perduoti `.zip` failo rankiniu būdu.

---

## 5 žingsnis — Importuoti paketą į TAK klientą

Atsisiųskite `.zip` failą ir importuokite:

**iTAK (iOS)**
Settings → Network → Servers → **+** → Upload Server Package → pasirinkite `.zip`

**ATAK (Android)**
Hamburger meniu → Settings → Network Preferences → TAK Servers → **+** → Import from file → pasirinkite `.zip`

**WinTAK (Windows)**
Hamburger meniu → **Import Manager** → Import → pasirinkite `.zip`

> **WinTAK pastaba:** Nenaudokite „Install CA" arba „Install Client Cert" langų — jie skirti tik rankiniam sertifikatų diegimui. Import Manager vienu veiksmu įdiegs serverio ryšį, sertifikatus ir žemėlapių šaltinius.

Serverio įrašas atsiras automatiškai. Paspauskite **Connect**.

---

## Žemėlapių šaltiniai

40+ ATAK suderinami žemėlapių šaltiniai (Bing, Google, ESRI, USGS, OpenTopo, OpenSeaMap, Estijos Maa-amet, Ukrainos Visicom ir kt.) pasiekiami administravimo skydelio skiltyje **Maps**, adresu `https://<SERVERIO_IP>:8889/maps`.

**Atsisiųsti visus iš karto (rekomenduojama):**
1. Atidarykite `https://<SERVERIO_IP>:8889/maps` → spustelėkite **[Download All as ZIP]**
2. Išskleiskite `tak-maps.zip` į aplanką
3. ATAK/WinTAK → hamburger → **Import Manager** → Import → pasirinkite išsklestą aplanką arba atskirus XML failus

**Atsisiųsti atskirus šaltinius:**
1. Įrenginyje atidarykite naršyklę → `https://<SERVERIO_IP>:8889/maps`
2. Paspauskite ant `.xml` failo, kad atsisiųstumėte
3. ATAK/WinTAK → hamburger → **Import Manager** → pasirinkite failą

---

## Kliento papildiniai

ATAK papildiniai — tai APK failai, diegiami Android įrenginiuose, o ne serveryje. TAK serveris automatiškai palaiko visus standartinius papildinius per savo vidinius API.

### Papildinių įkėlimas į serverį platinimui

Nukopijuokite APK failus į serverį, kad komandos įrenginiai galėtų juos atsisiųsti administravimo skydelio skiltyje **Plugins**, adresu `https://<SERVERIO_IP>:8889/plugins`:

```bash
cd ~/tak-server

make add-plugin APK=/kelias/iki/ATAK-Plugin-datasync-4.0.4-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-uastool-13.0.0-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-icetak-2.0.2-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-hammer-1.2-...-release.apk

# Peržiūrėkite įkeltus papildinius
make list-plugins
```

Android įrenginyje: atidarykite naršyklę → `https://<SERVERIO_IP>:8889/plugins` → paspauskite ant failo → ATAK → **Settings → Manage Plugins → Install from file**.

---

### DataSync

Sinchronizuoja misijas, žemėlapių sluoksnius, duomenų paketus ir failus tarp visų prijungtų ATAK įrenginių per TAK serverį.

> **Serverio reikalavimai:** Jokie. Mission API jau veikia TAK serveryje adresu `https://<serveris>:8443/Marti/api/missions`. Papildomos konfigūracijos nereikia.

**Diegimas įrenginyje:**
1. Atsisiųskite DataSync APK administravimo skydelio skiltyje **Plugins**, adresu `https://<SERVERIO_IP>:8889/plugins`
2. ATAK → **Settings → Manage Plugins → Install from file** → pasirinkite APK
3. Iš naujo paleiskite ATAK, jei paprašoma
4. DataSync atsiranda ATAK įrankių juostoje (sinchronizavimo piktograma)

DataSync serverio adresą nuskaito iš jūsų `.zip` duomenų paketo — papildomos konfigūracijos nereikia.

---

### UAS Tool

Rodo dronų vaizdo įrašą kaip „picture-in-picture" ant ATAK žemėlapio ir vaizduoja UAV takelius iš MAVLink tilto atskirame valdymo skydelyje.

> **EFDI integracija:** Kai MAVLink bridge veikia, UAS Tool automatiškai rodo visus MAVLink prijungtus dronus kaip mėlynas UAV piktogramas žemėlapyje. Vaizdo srauto URL konfigūruojamas UAS Tool nustatymuose kiekvienam dronui atskirai.

**Diegimas:** Ta pati APK diegimo procedūra kaip DataSync.

Galimi du variantai:
- **UAS Tool** — standartinis, bet kuriam suderinamam dronui
- **UAS Tool DIUBLUE** — Blue UAS sąraše esantiems dronams (Skydio, Autel, Parrot)

---

### ICE Voice (iceTAK)

Šifruotas „push-to-talk" balsas per TAK tinklą naudojant XMPP/ICE protokolą. Naudoja esamą TCP ryšį su TAK serveriu — papildomos serverio konfigūracijos nereikia.

**Diegimas:** Ta pati APK diegimo procedūra.

---

### Hammer

Struktūrizuotos taktinės ataskaitos — 9-linijinis MEDEVAC, CAS (artima oro parama), SALUTE, SPOT ataskaitos. Siunčia ataskaitas kaip CoT pranešimus, matomus visiems prijungtiems įrenginiams.

**Diegimas:** Ta pati APK diegimo procedūra.

---

## Priežiūra

```bash
cd ~/tak-server

# Atsisiųsti naujausią kodą, perstatyti, paleisti iš naujo — automatiškai
# save patikrina ir atsistato pats, jei kas nepavyko
./update.sh

# Patikrinti, ar diegimas šiuo metu veikia tinkamai, neatsisiunčiant kodo —
# saugu leisti bet kada (pvz., per cron), taip pat automatiškai atsistato
./health.sh

# Priverstinai pašalinti visus vartotojo sertifikato/paketo failus, nesvarbu
# kokia dabartinė būsena — naudokite, jei vartotojas "įstrigo" (pvz.
# rodo „jau egzistuoja" po ištrynimo)
./purge_user.sh <vardas>

# Pašalinti konteinerius/atvaizdus ir įdiegti iš naujo — duomenų bazė,
# sertifikatai, paketai ir takserver.env išsaugomi
./reinstall.sh
```

`update.sh` ir `health.sh` abu patikrina, ar diegti konteineriai iš tikrųjų atitinka atsisiųstą kodą — ne tik tai, kad `git pull` pavyko. Jei Docker kešas tyliai panaudoja pasenusį sluoksnį (taip gali nutikti), jie automatiškai priverstinai perstato be kešo ir patikrina dar kartą, užuot palikę sugadintą diegimą jums pačiam derinti.

Jei administravimo skydelis kada nors taptų nepasiekiamas, du skriptai repozitorijos šaknyje suteikia atsarginį variantą — jiems reikia tik SSH/shell prieigos prie serverio, ne tinklo prieigos prie 8889 prievado. `./get_package.sh [vardas]` be argumento parodo prieinamus paketus, o su vardu — atsisiunčia paketą į dabartinį aplanką. `./admin_fallback.sh` atidaro interaktyvų meniu tai pačiai skaitymo režimo paketų ir žemėlapių naršymo/atsisiuntimo funkcijai.

## Dažnos problemos

> **Nepavyksta atsisiųsti paketo įrenginyje**
> Patikrinkite, ar įrenginys pasiekia serverio IP per prievadą 8889 (administravimo skydelis). A variantas: įsitikinkite, kad įrenginys yra tame pačiame Wi-Fi/LAN tinkle. B variantas: patikrinkite, ar NetBird programėlė rodo **Connected**.

> **Serveris matomas, bet neprisijungia**
> Paketas gali būti sugeneruotas su netinkamu serverio IP. Ištrinkite serverio įrašą, sugeneruokite paketą iš naujo su `./generate_user.sh JusuŠaukinys-iTAK` (arba `-ATAK`/`-WinTAK`) ir importuokite pakartotinai.

> **iTAK neparodo serverio importavus paketą**
> Įsitikinkite, kad šaukinys baigiasi `-iTAK`, o ne `-ATAK`/`-WinTAK` — iTAK reikia savo paketo struktūros (žr. 4 žingsnį). Paleiskite `./health.sh`, kad patikrintumėte, ar paketų generatorius veikia tinkamai.

> **„Šaukinys jau egzistuoja" kuriant vartotoją, kurį maniniate ištrynę**
> Paleiskite `./purge_user.sh <vardas>`, kad priverstinai pašalintumėte likusius sertifikato/paketo failus, tada sukurkite iš naujo.

> **Ryšys nutrūksta užgęsus ekranui**
> Išjunkite energijos taupymo optimizaciją TAK programėlei.
> - **Android:** Settings → Apps → ATAK → Battery → **Unrestricted**
> - **iOS:** išjunkite **Low Power Mode** Settings → Battery
