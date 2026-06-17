# TAK Server Production Setup

A fully reproducible official Java TAK Server deployment with NetBird, Docker, and ATAK/iTAK/WinTAK support.

## Prerequisites

- Proxmox host
- NetBird account at [app.netbird.io](https://app.netbird.io) (optional — you can also use a plain IP)
- Android/iOS/Windows device with a TAK client (ATAK/iTAK/WinTAK)

---

## Step 1 — Create LXC Container (Proxmox host)

```bash
# Download Ubuntu 22.04 template
pveam update
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst

# Create container (adjust VMID, IP, gateway as needed)
pct create <VMID> local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname takserver \
  --cores 4 \
  --memory 6144 \
  --swap 1024 \
  --rootfs local-lvm:20 \
  --net0 name=eth0,bridge=vmbr0,ip=<CT_IP>/24,gw=<GATEWAY_IP> \
  --nameserver <DNS_IP> \
  --unprivileged 1 \
  --features nesting=1 \
  --start 1
```

---

## Step 2 — Enter Container and Deploy

```bash
pct enter <VMID>

apt update && apt upgrade -y
apt install -y git curl

git clone https://github.com/ndukve/TAK.git /opt/TAK
cd /opt/TAK

# Run installer — asks all required questions interactively
./install.sh
```

The installer will:

1. Detect NetBird (`wt0` interface) or offer to install it / accept a manual IP
2. Prompt for certificate metadata (country, state, city, org)
3. Auto-generate all secrets (Postgres passwords, cert passwords)
4. Build the Docker image and start all 7 services
5. `firstrun.sh` runs automatically inside the initialization container — generates certs and initialises the database schema (~2 min)

---

## Step 3 — Generate User Package

```bash
./generate_user.sh myusername
```

Then on your device, open a browser and download the package:

```
http://<SERVER_ADDRESS>:8888/myusername.zip
```

Import it in your TAK client:

**iTAK (iOS)**
Settings → Network → Servers → **+** → Upload Server Package → select the `.zip`

**ATAK (Android)**
Hamburger menu → Settings → Network Preferences → TAK Servers → **+** → Import from file → select the `.zip`

**WinTAK (Windows)**
Settings → Network Preferences → Server Connections → **+** → Import → select the `.zip`

---

## Ports

| Port | Protocol | Purpose                              |
|------|----------|--------------------------------------|
| 8089 | TCP/SSL  | CoT (TAK clients — primary)          |
| 8443 | HTTPS    | Marti API (iOS prefers HTTPS)        |
| 8888 | HTTP     | Client package download server       |

---

## Management

```bash
# View all logs
docker compose --env-file takserver.env logs -f

# View database logs only
make logs-db

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

Pull the latest config from git and rebuild in one step:

```bash
./update.sh
# or: make update
```

This pulls from GitHub, rebuilds the image, and restarts containers. Your `takserver.env` and data volumes are never touched.

---

## Notes

- All secrets are stored only in `takserver.env` — never committed to git
- Data persists in Docker volumes (`takserver_data`, `takdb_data`) even if containers are recreated
- To change the server address, update `TAK_SERVER_ADDRESS` in `takserver.env` and run `docker compose --env-file takserver.env up -d`
- To reset certificates and re-run first-time init, remove the `takserver_data` volume: `docker compose down -v && docker compose --env-file takserver.env up -d`

## TAK Client Known Issues

**Battery saving drops the connection (iOS and Android)**
Any battery saving mode — iOS Low Power Mode or Android Battery Saver — aggressively suspends background network activity and will drop the TAK connection. Turn these off when using iTAK or ATAK.

On Android, also set both ATAK to unrestricted battery usage:
- Settings → Apps → ATAK → Battery → **Unrestricted**

**Connection drops when the app is backgrounded**
Both iOS and Android suspend network sockets when apps go to the background. Keep iTAK/ATAK in the foreground during active use. To reconnect manually:
- **iTAK**: Settings → Network → Servers → tap the server → reconnect
- **ATAK**: Settings → Network Preferences → TAK Servers → tap the server → reconnect
