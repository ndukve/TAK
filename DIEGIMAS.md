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

Serveryje paleiskite:

```bash
cd ~/tak-server
./generate_user.sh JusuŠaukinis
```

Ši komanda sugeneruoja duomenų paketą su kliento sertifikatu ir serverio ryšio konfigūracija. Įrenginio naršyklėje atidarykite:

```
http://<SERVERIO_IP>:8888/JusuŠaukinis.zip
```

Vietoje `<SERVERIO_IP>` naudokite:
- **A variantas:** serverio LAN IP (pvz. `192.168.1.50`)
- **B variantas:** serverio NetBird IP — gaukite komanda:

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
Hamburger meniu → **Import Manager** → Import → pasirinkite `.zip`

> **WinTAK pastaba:** Nenaudokite „Install CA" arba „Install Client Cert" langų — jie skirti tik rankiniam sertifikatų diegimui. Import Manager vienu veiksmu įdiegs serverio ryšį, sertifikatus ir žemėlapių šaltinius.

Serverio įrašas atsiras automatiškai. Paspauskite **Connect**.

---

## Žemėlapių šaltiniai

40+ ATAK suderinami žemėlapių šaltiniai (Bing, Google, ESRI, USGS, OpenTopo, OpenSeaMap, Estijos Maa-amet, Ukrainos Visicom ir kt.) pasiekiami adresu `http://<SERVERIO_IP>:8888/maps/`.

**Atsisiųsti visus iš karto (rekomenduojama):**
1. Atidarykite `http://<SERVERIO_IP>:8888/maps/` → spustelėkite **[Download All as ZIP]**
2. Išskleiskite `tak-maps.zip` į aplanką
3. ATAK/WinTAK → hamburger → **Import Manager** → Import → pasirinkite išsklestą aplanką arba atskirus XML failus

**Atsisiųsti atskirus šaltinius:**
1. Įrenginyje atidarykite naršyklę → `http://<SERVERIO_IP>:8888/maps/`
2. Paspauskite ant `.xml` failo, kad atsisiųstumėte
3. ATAK/WinTAK → hamburger → **Import Manager** → pasirinkite failą

---

## Kliento papildiniai

ATAK papildiniai — tai APK failai, diegiami Android įrenginiuose, o ne serveryje. TAK serveris automatiškai palaiko visus standartinius papildinius per savo vidinius API.

### Papildinių įkėlimas į serverį platinimui

Nukopijuokite APK failus į serverį, kad komandos įrenginiai galėtų juos atsisiųsti adresu `http://<SERVERIO_IP>:8888/plugins/`:

```bash
cd ~/tak-server

make add-plugin APK=/kelias/iki/ATAK-Plugin-datasync-4.0.4-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-uastool-13.0.0-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-icetak-2.0.2-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-hammer-1.2-...-release.apk

# Peržiūrėkite įkeltus papildinius
make list-plugins
```

Android įrenginyje: atidarykite naršyklę → `http://<SERVERIO_IP>:8888/plugins/` → paspauskite ant failo → ATAK → **Settings → Manage Plugins → Install from file**.

---

### DataSync

Sinchronizuoja misijas, žemėlapių sluoksnius, duomenų paketus ir failus tarp visų prijungtų ATAK įrenginių per TAK serverį.

> **Serverio reikalavimai:** Jokie. Mission API jau veikia TAK serveryje adresu `https://<serveris>:8443/Marti/api/missions`. Papildomos konfigūracijos nereikia.

**Diegimas įrenginyje:**
1. Atsisiųskite DataSync APK iš `http://<SERVERIO_IP>:8888/plugins/`
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

## Dažnos problemos

> **Nepavyksta atsisiųsti paketo įrenginyje**
> Patikrinkite, ar įrenginys pasiekia serverio IP per prievadą 8888. A variantas: įsitikinkite, kad įrenginys yra tame pačiame Wi-Fi/LAN tinkle. B variantas: patikrinkite, ar NetBird programėlė rodo **Connected**.

> **Serveris matomas, bet neprisijungia**
> Paketas gali būti sugeneruotas su netinkamu serverio IP. Ištrinkite serverio įrašą, sugeneruokite paketą iš naujo su `./generate_user.sh JusuŠaukinys` ir importuokite pakartotinai.

> **Ryšys nutrūksta užgęsus ekranui**
> Išjunkite energijos taupymo optimizaciją TAK programėlei.
> - **Android:** Settings → Apps → ATAK → Battery → **Unrestricted**
> - **iOS:** išjunkite **Low Power Mode** Settings → Battery
