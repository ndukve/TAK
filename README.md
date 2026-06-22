# TAK Server Production Setup

A fully reproducible official Java TAK Server deployment with NetBird, Docker, and ATAK/iTAK/WinTAK support.

## Prerequisites

- A server or VM running Ubuntu 22.04 (minimal install)
- NetBird account at [app.netbird.io](https://app.netbird.io) — the installer can set it up for you
- Android/iOS/Windows device with a TAK client (ATAK/iTAK/WinTAK)

**Recommended VM specs:** 4 cores · 6–8 GB RAM · 40 GB disk

---

## Step 1 — Install Ubuntu 22.04

Boot from the Ubuntu 22.04 Server ISO and choose **Minimal install**. No extra packages needed — the installer handles everything.

---

## Step 2 — Deploy

Open a terminal on the server and run:

```bash
curl -fsSL https://raw.githubusercontent.com/ndukve/TAK/main/install.sh | bash
```

The installer will ask:

**Networking — two options:**
- **Option 1 — Install & connect NetBird** (recommended): paste your setup key from [app.netbird.io](https://app.netbird.io) → Keys. NetBird is installed and connected automatically, and the TAK server uses your NetBird IP.
- **Option 2 — Manual IP**: enter the server's IP address directly (use this if you already have NetBird running or want to use a LAN IP).

Then it prompts for certificate metadata (country, state, city, org), generates all secrets automatically, builds the Docker image, and starts all services.

First-run takes ~2 minutes to generate certificates and initialise the database. When done, all services are up on:

| Port | Purpose |
|------|---------|
| 8089 | TAK clients (SSL CoT) |
| 8443 | HTTPS API |
| 8888 | Package download |

---

## Step 3 — Generate User Package

```bash
cd ~/tak-server
./generate_user.sh <username>
```

Download the package on the device:

```
http://<SERVER_ADDRESS>:8888/<username>.zip
```

Import in the TAK client:

**iTAK (iOS)**
Settings → Network → Servers → **+** → Upload Server Package → select the `.zip`

**ATAK (Android)**
Hamburger menu → Settings → Network Preferences → TAK Servers → **+** → Import from file → select the `.zip`

**WinTAK (Windows)**
Settings → Network Preferences → Server Connections → **+** → Import → select the `.zip`

---

## Management

```bash
# View all logs
docker compose --env-file takserver.env logs -f

# Restart all services
docker compose --env-file takserver.env restart

# Stop all services
docker compose --env-file takserver.env down

# Add new user
./generate_user.sh <username>
# or: make add-user USERNAME=<username>

# List generated packages
make list-packages

# Service status
make status

# Shell into config container
make shell
```

### Updating

```bash
./update.sh
# or: make update
```

Pulls from GitHub, rebuilds the image, and restarts containers. `takserver.env` and data volumes are never touched.

---

## Notes

- All secrets are in `takserver.env` — never committed to git
- Data persists in Docker volumes even if containers are recreated
- To reset and re-run first-time init: `docker compose down -v && docker compose --env-file takserver.env up -d`

---

## TAK Client Known Issues

**Battery saving drops the connection (iOS and Android)**
iOS Low Power Mode and Android Battery Saver suspend background network activity. Turn these off when using iTAK or ATAK.

On Android: Settings → Apps → ATAK → Battery → **Unrestricted**

**Connection drops when the app is backgrounded**
Keep iTAK/ATAK in the foreground during active use. To reconnect manually:
- **iTAK**: Settings → Network → Servers → tap the server → reconnect
- **ATAK**: Settings → Network Preferences → TAK Servers → tap the server → reconnect
