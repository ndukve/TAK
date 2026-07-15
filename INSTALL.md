## Before You Start

You will need:

- A machine running **Ubuntu 22.04** (server edition, minimal install) with internet access
- A TAK client: **iTAK** (iOS), **ATAK** (Android), or **WinTAK** (Windows)

**Minimum server specs:** 4 CPU cores · 8 GB RAM · 64 GB disk

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

Each user needs a data package (`.zip`) that contains:

| File | Purpose |
|---|---|
| `<callsign>.p12` | **Client certificate** — proves the device's identity to the server (mTLS) |
| `truststore-root.p12` | **CA trust store** — lets the device verify the server's certificate |
| `blueteam.pref` | Server address, port, and cert settings |

Both certificate files are required. The client cert authenticates the device to the server; the trust store authenticates the server to the device.

### Certificates, routing groups, affiliation, and team colors

These are independent TAK concepts:

| Concept | Example | Purpose |
|---|---|---|
| Client certificate | `Alpha1-iTAK` | Uniquely authenticates one client installation. Do not reuse it on another device. |
| Server routing group | `TAK-USERS` | Controls which authenticated clients can exchange CoT. This deployment grants both IN and OUT access. |
| CoT affiliation | Friendly, hostile, neutral, unknown | Controls tactical affiliation symbology such as friendly rectangles or hostile diamonds. |
| TAK team color | Cyan, Red, Green, Yellow | A client-side operational team attribute; it does not grant server access. |

Every client still receives its own certificate. Clients can see one another because those separate certificates share the `TAK-USERS` routing group, not because they share credentials or a team color. Internal CoT arriving on TCP port 8087 is assigned to the same routing group so those tracks follow the same TAK Server route.

`TAK-USERS` is the default name. To use another access-group name, set `TAK_USER_GROUP=<name>` in `takserver.env`, rebuild/restart the TAK containers, and repair existing certificate memberships as shown below. Changing this value does not alter map symbols, affiliations, or team colors.

**The callsign must end in `-ATAK`, `-WinTAK`, or `-iTAK`** — e.g. `Alpha1-iTAK`. This isn't cosmetic: iTAK's importer requires a different zip layout (cert files at the root) than ATAK/WinTAK's Mission Package format (nested under `content/`), and the suffix is how the package builder knows which one to produce. Using the wrong client type will import silently with no server entry appearing.

### Standard flow (generate + authorise in one step)

```bash
cd ~/tak-server
./users.sh create Alpha1-iTAK
```

Run it with no argument and it will prompt you interactively for the callsign.

Same thing from the admin panel: **Users → New User** — enter the callsign and pick the client type from the dropdown; it appends the suffix for you.

### Split flow (prepare ahead, authorise later)

If you want to pre-generate packages without granting access yet — for example, staging kit before an operation — use the underlying scripts directly:

```bash
docker compose exec -T -e CLIENT_CERT_NAME=Alpha1-iTAK takserver_config \
    bash /opt/scripts/gen_client_cert.sh

docker compose exec -T -e CLIENT_CERT_NAME=Alpha1-iTAK -e TAK_SERVER_ADDRESS=<SERVER_IP> takserver_config \
    bash /opt/scripts/make_pkg_zip.sh

# Authorise when ready to grant access
docker compose exec -T -e USER_CERT_NAME=Alpha1-iTAK takserver_config \
    bash /opt/scripts/enable_user.sh
```

Once the package is ready, download it from the admin panel at `https://<SERVER_IP>:8889` — **Packages** tab.

For an existing deployment created before shared routing-group assignment was enabled, run this once after updating and restarting the server:

```bash
./users.sh repair-groups
```

It re-applies authorization to every packaged ATAK, iTAK, and WinTAK certificate with both IN and OUT membership in `TAK-USERS`. It does not replace certificates or make clients share private keys.

Replace `<SERVER_IP>` with:
- **Option A:** the server's LAN IP (e.g. `192.168.1.50`)
- **Option B:** the server's NetBird IP — find it with:

```bash
ip addr show wt0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
```

Generating a package through the admin panel also creates (or reuses) a login for that person: username is their base callsign (e.g. `Alpha1`, the suffix stripped), with a password shown once at creation time. Hand that password to the user out of band and they can log into the admin panel themselves from their phone or laptop, see only their own packages, and download them directly — no need for the operator to transfer the `.zip` by hand.

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

40+ ATAK-compatible map sources (Bing, Google, ESRI, USGS, OpenTopo, OpenSeaMap, Estonia Maa-amet, Ukraine Visicom, and more) are served from the admin panel's **Maps** tab at `https://<SERVER_IP>:8889/maps`.

**Download all at once (recommended):**
1. Navigate to `https://<SERVER_IP>:8889/maps` and click **[Download All as ZIP]**
2. Extract `tak-maps.zip` to a folder
3. ATAK/WinTAK → hamburger → **Import Manager** → Import → select the extracted folder or individual XML files

**Download individual sources:**
1. Open browser on device → `https://<SERVER_IP>:8889/maps`
2. Tap any `.xml` to download
3. ATAK/WinTAK → hamburger → **Import Manager** → select the file

---

## Client Plugins

ATAK plugins are APK files installed on Android devices — they do not go on the server. The TAK Server automatically supports all standard plugins through its existing APIs.

### Uploading Plugins for Distribution

Copy APKs to the server so team devices can download them from the admin panel's **Plugins** tab at `https://<SERVER_IP>:8889/plugins`:

```bash
cd ~/tak-server

make add-plugin APK=/path/to/ATAK-Plugin-datasync-4.0.4-...-release.apk
make add-plugin APK=/path/to/ATAK-Plugin-uastool-13.0.0-...-release.apk
make add-plugin APK=/path/to/ATAK-Plugin-icetak-2.0.2-...-release.apk
make add-plugin APK=/path/to/ATAK-Plugin-hammer-1.2-...-release.apk

# List what is published
make list-plugins
```

On the Android device: open a browser → navigate to `https://<SERVER_IP>:8889/plugins` → tap each file to sideload → ATAK → **Settings → Manage Plugins → Install from file**.

---

### DataSync

Synchronises missions, map overlays, data packages, and files between all connected ATAK devices through the TAK Server.

> **Server requirement:** None. The Mission API is built into TAK Server and runs automatically at `https://<server>:8443/Marti/api/missions`. No additional configuration required.

**Install on device:**
1. Download the DataSync APK from the admin panel's **Plugins** tab at `https://<SERVER_IP>:8889/plugins`
2. ATAK → **Settings → Manage Plugins → Install from file** → select the APK
3. Restart ATAK if prompted
4. DataSync appears in the ATAK toolbar (sync icon)

DataSync reads the server connection from your existing `.zip` data package — no additional server address configuration needed.

---

### UAS Tool

Displays drone video feeds as picture-in-picture on the ATAK map, and shows UAV tracks from your MAVLink bridge in a dedicated flight control panel.

> **MAVLink integration:** With a MAVLink bridge running, UAS Tool automatically shows all MAVLink-connected drones as blue UAV icons on the map. Video feed URL is configured per-drone inside UAS Tool settings.

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

## Maintenance

```bash
cd ~/tak-server

# Pull latest code, rebuild, restart — self-tests and auto-recovers after
./update.sh

# Check the deployment is healthy right now, without pulling/rebuilding —
# safe to run anytime (e.g. from cron), and auto-recovers if something's wrong
./health.sh

# Re-run the installer any time — it detects an existing takserver.env and
# offers to reinstall (wipe containers/images, rebuild, keep the database/
# certs/packages) or fully reconfigure from scratch
./install.sh

# Force-remove all cert/package files for a user, regardless of current
# state — use this if a user is stuck (e.g. "already exists" after deleting)
./users.sh purge <name>
```

`update.sh` and `health.sh` both verify the deployed containers actually match the code that was pulled — not just that `git pull` succeeded. If Docker's build cache silently serves a stale layer (this can happen), they automatically force a clean rebuild and re-verify before declaring success, rather than leaving a broken deployment for you to debug by hand.

If the admin panel itself is ever unreachable, two scripts at the repo root give you a break-glass fallback — they only need SSH/shell access to the server, not network access to port 8889. `./users.sh get [name]` lists available packages with no argument, or downloads one to the current directory when given a name. `./admin_fallback.sh` opens an interactive menu covering the same read-only package and map browsing/downloading.

## Troubleshooting

> **Can't download the package on the device**
> Confirm the device can reach the server IP on port 8889 (the admin panel). For Option A: check that the device is on the same Wi-Fi/LAN. For Option B: confirm the NetBird app shows **Connected**.

> **Server appears but won't connect**
> The package may have been generated with the wrong server IP. Delete the server entry, regenerate the package with `./users.sh create YourCallsign-iTAK` (or `-ATAK`/`-WinTAK`), and re-import.

> **iTAK doesn't show the server after importing the package**
> Make sure the callsign ends in `-iTAK`, not `-ATAK`/`-WinTAK` — iTAK needs its own package layout (see Step 4). Run `./health.sh` to confirm the package builder itself is working correctly.

> **"Callsign already exists" when creating a user that you thought you deleted**
> Run `./users.sh purge <name>` to force-remove any leftover cert/package files, then create it again.

> **Connection drops when the screen turns off**
> Disable battery optimisation for the TAK app.
> - **Android:** Settings → Apps → ATAK → Battery → **Unrestricted**
> - **iOS:** disable **Low Power Mode** in Settings → Battery
