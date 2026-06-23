---
title: TAK Serveris — Diegimo instrukcija
description: TAK Server 5.7 diegimas Ubuntu 22.04 su NetBird tinklo perdanga. Apima serverio diegimą, klientų prijungimą, papildinių platinimą ir EFDI integraciją.
tags:
  - tak
  - diegimas
  - netbird
  - atak
date: 2026-06-23
---

## Prieš pradedant

Jums reikės:

- Kompiuterio su **Ubuntu 22.04** (serverio leidimas, minimalus diegimas) ir interneto ryšiu
- Nemokamos **NetBird paskyros** [app.netbird.io](https://app.netbird.io) — sukuria šifruotą tunelį tarp serverio ir jūsų įrenginių
- **NetBird programėlės** kiekviename įrenginyje, kuris jungiasi prie TAK
- TAK kliento programėlės: **iTAK** (iOS), **ATAK** (Android) arba **WinTAK** (Windows)

**Minimalūs serverio reikalavimai:** 4 CPU branduoliai · 6 GB RAM · 40 GB disko vietos

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

::: info
Diegimas trunka apie 5–10 minučių. Kai pasirodys suvestinės ekranas, serveris veikia.
:::

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

Serverio NetBird IP adresą galite gauti komanda:

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

make add-plugin APK=/kelias/iki/ATAK-Plugin-datasync-4.0.4-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-uastool-13.0.0-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-icetak-2.0.2-...-release.apk
make add-plugin APK=/kelias/iki/ATAK-Plugin-hammer-1.2-...-release.apk

# Peržiūrėkite įkeltus papildinius
make list-plugins
```

Android įrenginyje: atidarykite naršyklę → `http://<SERVERIO_NETBIRD_IP>:8888/plugins/` → paspauskite ant failo → ATAK → **Settings → Manage Plugins → Install from file**.

---

### DataSync

Sinchronizuoja misijas, žemėlapių sluoksnius, duomenų paketus ir failus tarp visų prijungtų ATAK įrenginių per TAK serverį.

::: tip Serverio reikalavimai
Jokie. Mission API jau veikia TAK serveryje adresu `https://<serveris>:8443/Marti/api/missions`. Papildomos konfigūracijos nereikia.
:::

**Diegimas įrenginyje:**
1. Atsisiųskite DataSync APK iš `http://<serveris>:8888/plugins/`
2. ATAK → **Settings → Manage Plugins → Install from file** → pasirinkite APK
3. Iš naujo paleiskite ATAK, jei paprašoma
4. DataSync atsiranda ATAK įrankių juostoje (sinchronizavimo piktograma)

DataSync serverio adresą nuskaito iš jūsų `.zip` duomenų paketo — papildomos konfigūracijos nereikia.

---

### UAS Tool

Rodo dronų vaizdo įrašą kaip „picture-in-picture" ant ATAK žemėlapio ir vaizduoja UAV takelius iš MAVLink tilto atskirame valdymo skydelyje.

::: tip EFDI integracija
Kai MAVLink bridge veikia, UAS Tool automatiškai rodo visus MAVLink prijungtus dronus kaip mėlynas UAV piktogramas žemėlapyje. Vaizdo srauto URL konfigūruojamas UAS Tool nustatymuose kiekvienam dronui atskirai.
:::

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

::: warning Nepavyksta atsisiųsti paketo įrenginyje
Patikrinkite, ar NetBird programėlė rodo **Connected**. Paketų serveris pasiekiamas tik per NetBird tinklą.
:::

::: warning Serveris matomas, bet neprisijungia
Paketas gali būti sugeneruotas su netinkamu serverio IP. Ištrinkite serverio įrašą, sugeneruokite paketą iš naujo su `./generate_user.sh JusuŠaukinis` ir importuokite pakartotinai.
:::

::: warning Ryšys nutrūksta užgęsus ekranui
Išjunkite energijos taupymo optimizaciją TAK programėlei.

- **Android:** Settings → Apps → ATAK → Battery → **Unrestricted**
- **iOS:** išjunkite **Low Power Mode** Settings → Battery
:::

