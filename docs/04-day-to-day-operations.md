# 04 — Day-to-Day Operations

Most of this happens either through the **admin panel** (simpler, recommended) or via **`make`** commands in a terminal (when the WebUI isn't available, or you need to script it).

## New user

**Admin panel:** Users → New User → callsign + client type (ATAK/WinTAK/iTAK/Service).

**Terminal** — generates the cert, builds the package, AND authorizes it on the server in one step:

```bash
make add-user USERNAME=alice-iTAK   # must end in -ATAK / -WinTAK / -iTAK
```

Finer-grained control (if you need to split the steps):

```bash
make gen-device-cert USERNAME=alice-iTAK   # cert only (.p12), not yet authorized
make make-package USERNAME=alice-iTAK      # build the .zip from an existing cert
make gen-cert USERNAME=alice-iTAK          # both of the above, still not authorized
make enable-user USERNAME=alice-iTAK       # authorize an already-generated cert
```

The package is downloaded via `http://<server>:8888/<username>.zip` or from the admin panel (Packages → Download).

## Listing users

```bash
make list-packages
```

Or in the admin panel: Packages.

## Plugins

**Client plugin** (APK, downloaded through the client):

```bash
make add-plugin APK=/path/to/plugin.apk
make list-plugins
```

**Server plugin** (JAR, changes `takserver_pluginmanager` behavior):

```bash
make install-plugin JAR=/path/to/plugin.jar
```

Or in the admin panel: Plugins.

## Basemaps

Admin panel: Basemaps — ESRI/Google composite basemaps, environmental overlays (NOAA radar, NASA IMERG, GOES), TAK distribution to connected EUDs (End User Devices).

## Machine integrations (service accounts)

A certificate for a machine integration (e.g. an EFDI moon-pod), without a TAK client package:

```bash
make add-service NAME=efdi-pod
```

## Resetting the admin panel password

`scripts/reset_admin_password.sh` is not a command: it only defines the function that `health.sh` calls. To set a new password for the admin panel's `admin` account, read it silently and call the function as root from the repository directory:

```bash
cd ~/tak-server
read -rs -p 'New admin password: ' P; echo
sudo bash -c '. scripts/reset_admin_password.sh; reset_admin_password takserver.env admin "$1"' _ "$P"
unset P
```

It writes a fresh bcrypt hash into `admin_users`. The password shows in the process list for a moment, which is acceptable on a single-user host. Setting `ADMIN_FIRST_PASS` again does nothing once the account exists. The installer's closing screen prints the first password in plain text, so change it straight after installing.

## Status and logs

```bash
make status      # services + listening ports
make logs         # all service logs (follow mode)
make logs-db      # takdb logs only
make shell        # bash into the takserver_config container
```

Admin panel: Dashboard (overall status), Logs (superadmin).

## If the WebUI is unreachable

`./scripts/admin_fallback.sh` — an interactive terminal menu to browse and download packages/maps. Read-only (no create/delete), requires SSH access to the server. See [09-troubleshooting.md](09-troubleshooting.md).

## CoT retention and data location

The server keeps its data under `TAK_DATA_DIR` (default `/srv/tak-data`) on the host, not in Docker volumes (see doc 08). CoT history is purged by the retention service from two keys in `takserver.env`: `TAK_RETENTION_COT_DAYS` (days to keep, or `null` for forever) and `TAK_RETENTION_CRON` (a Spring cron for the purge run). The default schedule `-` keeps the service idle, so a server where both are unset never deletes anything and the database grows without limit when a gateway streams CoT into it (20 GB in 12 hours was seen). After changing them, recreate the container: `docker compose --env-file takserver.env up -d --force-recreate takserver_retention`. Check the size with `df -h /` and `select pg_size_pretty(pg_database_size('cot'))` in the `takdb` container. Deleted rows are reused by new data but the files shrink only after a `VACUUM FULL`.

## Groups (channels)

ATAK shows TAK Server groups as channels. **Admin panel → Groups** (superadmin) lists every group with its members and changes a user's groups: *add* groups to what they have, *remove* some, or *replace* them all, each as send and receive, send only, or receive only. It runs TAK Server's own `UserManager.jar certmod` (the tool `enable_user.sh` uses), so nothing edits `UserAuthenticationFile.xml` by hand. A group exists once a user is in it; there is no separate "create group" step. New packages still go into `TAK_USER_GROUP` (default `TAK-USERS`) with send and receive, and `users.sh repair-groups` still assigns only that group, so run it with care after you build other groups (it replaces a user's groups with the shared one). Service accounts (names ending `-Service`, EFDI's own feed among them) can only gain groups from the panel, never lose or swap them. To have EFDI's tracks reach a channel, add `efdi-gateway-Service` to that group. A change applies to a client's next connection; reconnect an already connected client. The group `revoked` is where TAK keeps revoked certificates and cannot be assigned here: disable the user instead. Not yet tried against the live server: the effect on an already connected client.
