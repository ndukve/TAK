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

## Status and logs

```bash
make status      # services + listening ports
make logs         # all service logs (follow mode)
make logs-db      # takdb logs only
make shell        # bash into the takserver_config container
```

Admin panel: Dashboard (overall status), Logs (superadmin).

## If the WebUI is unreachable

`./admin_fallback.sh` — an interactive terminal menu to browse and download packages/maps. Read-only (no create/delete), requires SSH access to the server. See [09-troubleshooting.md](09-troubleshooting.md).
