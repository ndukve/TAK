# 06 — Network and Access

## How devices reach the server

Chosen during install (`install.sh` [1/7]), one of three:

| Option | When to use |
|---|---|
| **Local network (LAN/Wi-Fi)** — manual IP | All devices are on the same network as the server. Needs a static IP or a DHCP reservation. |
| **NetBird** | Remote connection over a WireGuard tunnel. Setup key from [app.netbird.io](https://app.netbird.io) → Keys. |
| **Tailscale** | Remote connection, alternative to NetBird. Auth key from [login.tailscale.com](https://login.tailscale.com) → Settings → Keys. |

If both NetBird and Tailscale are already running on the server, `install.sh` asks which one to use as `TAK_SERVER_ADDRESS`.

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| 8089 | TCP/TLS | CoT — primary TAK client connection (mTLS) |
| 8443 | HTTPS | Marti API |
| 8087 | TCP (plaintext) | Internal CoT input for service accounts, overlay network only (see `TAK_USER_GROUP` in `templates/CoreConfig.tpl`) — **do not expose to the public internet** |
| 8889 | HTTPS | Admin panel — WebUI, authenticated package/plugin/map downloads |
| 9000–9002 | TCP/TLS | Federation (see [05-certificates-and-security.md](05-certificates-and-security.md)) |

> **`Makefile` and the root `README.md` mention port 8888** as an anonymous package server — this is stale. The actual current path is `GET /api/packages/{name}/download` via the admin panel port **8889**, authenticated (`admin`/`superadmin`/`field` role). If a `:8888` download doesn't work, use the admin panel or `./admin_fallback.sh` instead.

## Downloading client packages

Through the admin panel (Packages → Download) or `./admin_fallback.sh` if the WebUI is unreachable. Requires authentication — there is no anonymous public package endpoint.

## Federating with another TAK server

See [05-certificates-and-security.md](05-certificates-and-security.md) and the `<federation>` block in `templates/CoreConfig.tpl`. Requires a mutual certificate exchange with the other side's TAK server.
