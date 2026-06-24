## Before You Start

You will need:

- A machine running **Ubuntu 22.04** (server edition, minimal install) with internet access
- A TAK client: **iTAK** (iOS), **ATAK** (Android), or **WinTAK** (Windows)

**Minimum server specs:** 4 CPU cores · 8 GB RAM · 40 GB disk

**Choose how devices will reach the server:**

| Scenario | What to use |
|---|---|
| All devices on the **same LAN or Wi-Fi** as the server | Use the server's local IP — no VPN needed |
| Devices connecting **remotely** (different network, internet) | Use NetBird or Tailscale overlay |

---

## Step 1 — Decide on Networking

### Option A — Local network (no VPN)

If your phones, laptops, and the TAK server are all on the same Wi-Fi or LAN, you do not need any VPN. The server's local IP (e.g. `192.168.1.50`) is the server address.

> **Assign a static IP** to the server (or a DHCP reservation on your router). If the IP changes, existing data packages will stop working.

Skip to Step 2. During the installer you will choose **"Enter address manually"** and type the server's LAN IP.

### Option B — Remote access (NetBird)

If devices will connect from outside the local network, use NetBird to create an encrypted overlay tunnel.

1. Sign in at [app.netbird.io](https://app.netbird.io)
2. Navigate to **Setup Keys** in the left sidebar
3. Click **Create setup key**, give it a name (e.g. `TAK`), click **Create**
4. Copy the key — you will need it in the next step

---

## Step 2 — Run the Installer

On your Ubuntu machine, open a terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/ndukve/TAK/main/install.sh | bash
```

> **The installer requires root.** If you are not already root, it will automatically re-run itself with `sudo` and prompt for your password once. The rest of the install runs unattended.

When prompted for networking, choose the option that matches Step 1:

- **Option 1 — Install & connect NetBird** → paste your setup key (Option B above)
- **Option 2 — Install & connect Tailscale** → paste your Tailscale auth key
- **Option 3 — Enter address manually** → type the server's LAN IP (Option A above)

The installer will:

- Install Docker Engine
- Connect to the chosen network (or skip if manual IP)
- Prompt for certificate metadata (country, state, city, organisation — defaults are fine for testing)
- Generate all secrets automatically
- Build the TAK Server image and start all services

> Installation takes approximately 5–10 minutes. When the summary screen appears, the server is running.

---

## Step 3 — Connect Your Device to the Network

**If you chose Option A (local network):** skip this step. Devices reach the server directly over LAN/Wi-Fi.

**If you chose Option B (NetBird):** install the NetBird app on each device that will connect to TAK.

1. Install the NetBird app:
   - iOS: [App Store](https://apps.apple.com/app/netbird/id6469329339)
   - Android: [Google Play](https://play.google.com/store/apps/details?id=io.netbird.client)
2. Open the app → tap **Connect with setup key** → paste the key from Step 1
3. Wait for the status to show **Connected**

---

## Step 4 — Generate a User Package

On the server, run:

```bash
cd ~/tak-server
./generate_user.sh YourCallsign
```

This generates a data package containing a client certificate and server connection config. On your device, open a browser and navigate to:

```
http://<SERVER_IP>:8888/YourCallsign.zip
```

Replace `<SERVER_IP>` with:
- **Option A:** the server's LAN IP (e.g. `192.168.1.50`)
- **Option B:** the server's NetBird IP — find it with:

```bash
ip addr show wt0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
```

---

## Step 5 — Import the Package into Your TAK Client

Download the `.zip` file and import it:

**iTAK (iOS)**
Settings → Network → Servers → **+** → Upload Server Package → select the `.zip`

**ATAK (Android)**
Hamburger menu → Settings → Network Preferences → TAK Servers → **+** → Import from file → select the `.zip`

**WinTAK (Windows)**
Hamburger menu → **Import Manager** → Import → select the `.zip`

> **WinTAK note:** Do not use the "Install CA" or "Install Client Cert" dialogs — those are for manual certificate installation only. The Import Manager handles the full package including server connection, certs, and map sources in one step.

The server entry will appear automatically. Tap **Connect**.

---

## Map Sources

40+ ATAK-compatible map sources (Bing, Google, ESRI, USGS, OpenTopo, OpenSeaMap, Estonia Maa-amet, Ukraine Visicom, and more) are served at `http://<SERVER_IP>:8888/maps/`.

**Download all at once (recommended):**
1. Navigate to `http://<SERVER_IP>:8888/maps/` and click **[Download All as ZIP]**
2. Extract `tak-maps.zip` to a folder
3. ATAK/WinTAK → hamburger → **Import Manager** → Import → select the extracted folder or individual XML files

**Download individual sources:**
1. Open browser on device → `http://<SERVER_IP>:8888/maps/`
2. Tap any `.xml` to download
3. ATAK/WinTAK → hamburger → **Import Manager** → select the file

---

## Client Plugins

ATAK plugins are APK files installed on Android devices — they do not go on the server. The TAK Server automatically supports all standard plugins through its existing APIs.

### Uploading Plugins for Distribution

Copy APKs to the server so team devices can download them at `http://<SERVER_IP>:8888/plugins/`:

```bash
cd ~/tak-server

make add-plugin APK=/path/to/ATAK-Plugin-datasync-4.0.4-...-release.apk
make add-plugin APK=/path/to/ATAK-Plugin-uastool-13.0.0-...-release.apk
make add-plugin APK=/path/to/ATAK-Plugin-icetak-2.0.2-...-release.apk
make add-plugin APK=/path/to/ATAK-Plugin-hammer-1.2-...-release.apk

# List what is published
make list-plugins
```

On the Android device: open a browser → navigate to `http://<SERVER_IP>:8888/plugins/` → tap each file to sideload → ATAK → **Settings → Manage Plugins → Install from file**.

---

### DataSync

Synchronises missions, map overlays, data packages, and files between all connected ATAK devices through the TAK Server.

> **Server requirement:** None. The Mission API is built into TAK Server and runs automatically at `https://<server>:8443/Marti/api/missions`. No additional configuration required.

**Install on device:**
1. Download the DataSync APK from `http://<SERVER_IP>:8888/plugins/`
2. ATAK → **Settings → Manage Plugins → Install from file** → select the APK
3. Restart ATAK if prompted
4. DataSync appears in the ATAK toolbar (sync icon)

DataSync reads the server connection from your existing `.zip` data package — no additional server address configuration needed.

---

### UAS Tool

Displays drone video feeds as picture-in-picture on the ATAK map, and shows UAV tracks from your MAVLink bridge in a dedicated flight control panel.

> **EFDI integration:** With the MAVLink bridge running, UAS Tool automatically shows all MAVLink-connected drones as blue UAV icons on the map. Video feed URL is configured per-drone inside UAS Tool settings.

**Install:** Same sideload procedure as DataSync.

Two variants are available:
- **UAS Tool** — standard, for any compatible drone
- **UAS Tool DIUBLUE** — for Blue UAS-cleared drones (Skydio, Autel, Parrot)

---

### ICE Voice (iceTAK)

Encrypted push-to-talk voice over the TAK network using the XMPP/ICE protocol. Uses the existing TCP connection to the TAK Server — no additional server configuration required.

**Install:** Same sideload procedure.

---

### Hammer

Structured tactical reporting — 9-line MEDEVAC, CAS (close air support), SALUTE, SPOT reports. Sends reports as CoT messages visible to all connected devices.

**Install:** Same sideload procedure.

---

## Troubleshooting

> **Can't download the package on the device**
> Confirm the device can reach the server IP on port 8888. For Option A: check that the device is on the same Wi-Fi/LAN. For Option B: confirm the NetBird app shows **Connected**.

> **Server appears but won't connect**
> The package may have been generated with the wrong server IP. Delete the server entry, regenerate the package with `./generate_user.sh YourCallsign`, and re-import.

> **Connection drops when the screen turns off**
> Disable battery optimisation for the TAK app.
> - **Android:** Settings → Apps → ATAK → Battery → **Unrestricted**
> - **iOS:** disable **Low Power Mode** in Settings → Battery
