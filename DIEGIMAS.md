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

## Dažnos problemos

**Nepavyksta atsisiųsti paketo įrenginyje**
Patikrinkite, ar NetBird programėlė rodo **Connected**. Paketų serveris pasiekiamas tik per NetBird tinklą.

**Serveris matomas, bet neprisijungia**
Paketas gali būti sugeneruotas su netinkamu serverio IP. Ištrinkite paketą, sugeneruokite iš naujo su `./generate_user.sh` ir importuokite pakartotinai.

**Ryšys nutrūksta užgęsus ekranui**
Išjunkite energijos taupymo optimizaciją TAK programėlei.
- Android: Settings → Apps → ATAK → Battery → **Unrestricted**
- iOS: išjunkite **Low Power Mode** Settings → Battery
