---
title: TAK Server — Installation Guide
description: Deploy TAK Server 5.7 on Ubuntu 22.04 with NetBird overlay networking. Covers server setup, client onboarding, plugin distribution, and EFDI integration.
tags:
  - tak
  - installation
  - netbird
  - atak
date: 2026-06-23
---

## Before You Start

You will need:

- A machine running **Ubuntu 22.04** (server edition, minimal install) with internet access
- A free **NetBird account** at [app.netbird.io](https://app.netbird.io) — provides the encrypted tunnel between the server and your devices
- The **NetBird app** installed on each device that will connect to TAK
- A TAK client: **iTAK** (iOS), **ATAK** (Android), or **WinTAK** (Windows)

**Minimum server specs:** 4 CPU cores · 6 GB RAM · 40 GB disk

---

## Step 1 — Create a NetBird Setup Key

A setup key lets devices join your private NetBird network.

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

When prompted for networking, choose **option 1 (Install & connect NetBird)** and paste your setup key. The installer will:

- Install Docker Engine
- Install and connect NetBird using your setup key
- Detect the NetBird IP (`wt0` interface) and use it as the server address
- Prompt for certificate metadata (country, state, city, organisation — defaults are fine for testing)
- Generate all secrets automatically
- Build the TAK Server image and start all services

::: info
Installation takes approximately 5–10 minutes. When the summary screen appears, the server is running.
:::

---

## Step 3 — Connect Your Device to NetBird

Each device that will connect to TAK must join the same NetBird network.

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
http://<SERVER_NETBIRD_IP>:8888/YourCallsign.zip
```

To retrieve the server's NetBird IP:

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
Settings → Network Preferences → Server Connections → **+** → Import → select the `.zip`

The server entry will appear automatically. Tap **Connect**.

---

## Client Plugins

ATAK plugins are APK files installed on Android devices — they do not go on the server. The TAK Server automatically supports all standard plugins through its existing APIs.

### Uploading Plugins for Distribution

Copy APKs to the server so team devices can download them at `http://<server>:8888/plugins/`:

```bash
cd ~/tak-server

make add-plugin APK=/path/to/ATAK-Plugin-datasync-4.0.4-...-release.apk
make add-plugin APK=/path/to/ATAK-Plugin-uastool-13.0.0-...-release.apk
make add-plugin APK=/path/to/ATAK-Plugin-icetak-2.0.2-...-release.apk
make add-plugin APK=/path/to/ATAK-Plugin-hammer-1.2-...-release.apk

# List what is published
make list-plugins
```

On the Android device: open a browser → navigate to `http://<SERVER_NETBIRD_IP>:8888/plugins/` → tap each file to sideload → ATAK → **Settings → Manage Plugins → Install from file**.

---

### DataSync

Synchronises missions, map overlays, data packages, and files between all connected ATAK devices through the TAK Server.

::: tip Server requirement
None. The Mission API is built into TAK Server and runs automatically at `https://<server>:8443/Marti/api/missions`. No additional configuration required.
:::

**Install on device:**
1. Download the DataSync APK from `http://<server>:8888/plugins/`
2. ATAK → **Settings → Manage Plugins → Install from file** → select the APK
3. Restart ATAK if prompted
4. DataSync appears in the ATAK toolbar (sync icon)

DataSync reads the server connection from your existing `.zip` data package — no additional server address configuration needed.

---

### UAS Tool

Displays drone video feeds as picture-in-picture on the ATAK map, and shows UAV tracks from your MAVLink bridge in a dedicated flight control panel.

::: tip EFDI integration
With the MAVLink bridge running, UAS Tool automatically shows all MAVLink-connected drones as blue UAV icons on the map. Video feed URL is configured per-drone inside UAS Tool settings.
:::

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

::: warning Can't download the package on the device
Confirm the NetBird app shows **Connected** on the device. The package server is only reachable over the NetBird network.
:::

::: warning Server appears but won't connect
The package may have been generated with the wrong server IP. Delete the server entry, regenerate the package with `./generate_user.sh YourCallsign`, and re-import.
:::

::: warning Connection drops when the screen turns off
Disable battery optimisation for the TAK app.

- **Android:** Settings → Apps → ATAK → Battery → **Unrestricted**
- **iOS:** disable **Low Power Mode** in Settings → Battery
:::

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-14 | Initial commit — forked from official efdi-moon-pod-main repository |
| 2026-06-15 | Base bridge adapters wired; repository structure established; README added |
| 2026-06-16 | airplanes.live bridge: regional ADS-B and global military aircraft |
| 2026-06-16 | ICAO NOTAM bridge: active NOTAM ingestion via ICAO Dataservices API |
| 2026-06-16 | FlightRadar24 bridge: FR24 commercial broadcast integration |
| 2026-06-16 | Windy bridge: point weather forecast API integration |
| 2026-06-16 | Protocol Buffer descriptors for new track types (aircraft_track, ais_track, aprs_track, cat62_track) |
| 2026-06-17/18 | Quality improvements: bridge stability, layer duplicate filtering, track fusion tuning |
| 2026-06-18 | ASTERIX full-decode design specification document |
| 2026-06-19/22 | Additional bridge and layer improvements; Giraffe ASTERIX bridge completed |
| 2026-06-22 | dronuradaras.lt bridge: acoustic sensor network and drone detection events |
| 2026-06-22 | CoT DETECTION section with audio recording URL in ATAK remarks field |
| 2026-06-22 | Radar site marker: published on startup + 60 s keepalive so ATAK does not lose the marker |
| 2026-06-23 | Security audit: hardcoded API key removed from register_topics.sh; key moved to `$EFDI_PORTAL_KEY` environment variable |
| 2026-06-23 | Security: personal namespace UUID, email, IP and vendor identifier removed from all tracked files; bridges read `PARTNER_NAMESPACE` from environment |
| 2026-06-23 | Security: `compose/.env` and `register_topics.sh` added to `.gitignore` — credentials remain local only |
| 2026-06-23 | Security: unbounded HTTP body read in `rest-http/bridge.py` limited to 10 MB |
| 2026-06-23 | Documentation update: INSTALL.md (English), DIEGIMAS.md (Lithuanian), README.md rewritten as architecture overview |
| 2026-06-23 | ASTERIX CAT-34 I034/120 decoder: radar self-reports WGS-84 position from live stream — manual coordinate configuration no longer required |
| 2026-06-23 | Mobile radar support: position, speed and heading derived from sequential I034/120 messages; ATAK shows movement track on vehicle-mounted radars |
