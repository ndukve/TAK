# FreeTAKServer Production Setup

A fully reproducible FTS deployment with Tailscale, Docker, and iTAK support.

## Prerequisites

- Proxmox host
- A Tailscale tailnet already created at [login.tailscale.com](https://login.tailscale.com) — devices can only join an existing tailnet
- Tailscale auth key
- Android/iOS/Windows device with a TAK client (ATAK/iTAK/WinTAK) and Tailscale installed

---

## Step 1 — Create LXC Container (Proxmox host)

```bash
# Download Ubuntu 22.04 template
pveam update
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst

# Create container (adjust VMID, IP, gateway as needed)
pct create <VMID> local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname <HOSTNAME> \
  --cores 2 \
  --memory 2048 \
  --swap 512 \
  --rootfs local-lvm:10 \
  --net0 name=eth0,bridge=vmbr0,ip=<CT_IP>/24,gw=<GATEWAY_IP> \
  --nameserver <DNS_IP> \
  --unprivileged 1 \
  --features nesting=1 \
  --start 1

# Add TUN device for Tailscale
echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> /etc/pve/lxc/<VMID>.conf
echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> /etc/pve/lxc/<VMID>.conf
pct reboot <VMID>
```

---

## Step 2 — Enter Container and Install Tailscale

```bash
pct enter <VMID>

# Fix locale
apt update && apt upgrade -y
apt install -y curl

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled

# Connect to tailnet (use invite link on mobile, auth key on server)
tailscale up --authkey=<YOUR_AUTH_KEY> --hostname=freetakserver --accept-routes

# Verify
tailscale ip -4
```

---

## Step 3 — Deploy FTS

```bash
apt install -y git

git clone https://github.com/ndukve/TAK.git /opt/TAK
cd /opt/TAK

# Run installer — asks all required questions interactively
./install.sh
```

---

## Step 4 — Generate User Package for iTAK

```bash
./generate_user.sh myusername
```

This generates `/opt/fts/certs/clientPackages/myusername.zip`.

Serve it:
```bash
make serve-packages
```

On your device, open Safari/browser and go to:
```
http://<TAILSCALE_IP>:8888/myusername.zip
```

In iTAK: **Settings → Network → Servers → + → Upload Server Package**

---

## Ports

| Port  | Protocol | Purpose          |
|-------|----------|------------------|
| 8087  | TCP      | CoT (TAK clients)|
| 8089  | TCP/SSL  | SSL CoT          |
| 19023 | TCP      | REST API         |
| 8090  | HTTP     | Web UI (FreeTAKServer-UI) |

---

## Management

```bash
# View logs
docker logs freetakserver -f

# Restart
docker compose restart

# Stop
docker compose down

# Rebuild after config changes
docker compose build && docker compose up -d

# Add new user
./generate_user.sh <username>
```

---

## Notes

- All patches (timeout fixes) are baked into the Dockerfile
- Data persists in `/opt/fts` even if container is recreated
- To change the IP, update `.env` and run `docker compose up -d`
- Certificate password is set in `.env` (default: `atakatak`)
