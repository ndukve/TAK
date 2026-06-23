# Installation Guide

This guide walks through deploying TAK Server on a fresh Ubuntu 22.04 machine. No prior experience with Docker or TAK is required.

---

## Before You Start

You will need:

- A machine running **Ubuntu 22.04** (server edition, minimal install) with internet access
- A free **NetBird account** at [app.netbird.io](https://app.netbird.io) — this provides the encrypted tunnel between the server and your devices
- The **NetBird app** installed on each device that will connect to TAK
- A TAK client on your device: **iTAK** (iOS), **ATAK** (Android), or **WinTAK** (Windows)

Minimum server specs: 4 CPU cores · 6 GB RAM · 40 GB disk

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

Installation takes approximately 5–10 minutes. When the summary screen appears, the server is running.

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

The server's NetBird IP is printed at the end of the installation output. You can also retrieve it with:

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

## Troubleshooting

**Can't download the package on the device**
Confirm the NetBird app shows **Connected** on the device. The package server is only reachable over the NetBird network.

**Server appears but won't connect**
The package may have been generated with the wrong server IP. Delete the package, regenerate with `./generate_user.sh`, and re-import.

**Connection drops when the screen turns off**
Disable battery optimisation for the TAK app.
- Android: Settings → Apps → ATAK → Battery → **Unrestricted**
- iOS: disable **Low Power Mode** in Settings → Battery
