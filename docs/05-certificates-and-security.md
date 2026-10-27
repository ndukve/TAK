# 05 — Certificates and Security

## Client onboarding (mTLS)

Every client gets its own certificate, signed by the server's CA. Certificates are generated once — during `firstrun.sh` — and stored in the `takserver_data` volume, **not** in the image.

> **Changing certificate passwords requires wiping the volume.** If you change `TAKSERVER_CERT_PASS` or `CA_PASS` in `takserver.env` after the first run, the JKS files already in the volume stay encrypted with the old password and no longer match. You need to delete the volumes (`docker compose down -v`) and let `firstrun.sh` regenerate everything — which means **every** previously issued client certificate stops working and has to be reissued.

Rebuilding the image does **not** regenerate certificates — they live in the volume. First-run regeneration occurs only after deleting the volume; use the server certificate renewal procedure below to replace only the server leaf without deleting client identities.

## TAK server certificate name

The server certificate keeps the internal common name `takserver` and includes `TAK_SERVER_ADDRESS` and, when set, `TAK_SERVER_ADDRESS_LAN` as subject alternative names (SANs). The TAK display name shown in new client packages is configured in **Settings → Branding**; it does not control certificate identity or network addresses. Command-line package creation continues to use `TAK_SERVER_NAME` from the env file.

For an existing installation, back up TAK data with `scripts/backup.sh`, then run `scripts/renew_server_cert.sh`. It replaces only the server certificate files under the existing CA, verifies the configured SANs, and restarts the TLS services. Existing client certificates remain signed by the same CA. Clients must import a newly generated package if their connection address changed.

## Admin panel authentication

- Local login: password (bcrypt), JWT access token (15 min), rotating refresh token (7 days) with theft detection — reusing an already-rotated refresh token revokes the whole session.
- Roles: `superadmin` / `admin` / `readonly` / `field`.
- Password rotation: 90 days; 5 failed attempts locks the account for 15 min.
- Optional OIDC SSO (Keycloak, Authentik, or any compliant IdP) — disabled by default, enabled by setting `OIDC_ISSUER`/`OIDC_CLIENT_ID`/`OIDC_CLIENT_SECRET`. IdP groups map to panel roles via `OIDC_ROLE_MAP`. See the comments in `takserver.env.example`.

## Docker socket isolation

The admin API has no direct access to the Docker socket. Every container operation goes through `docker_socket_proxy`, which allows only logs and exec on specific TAK services — no container create/delete, no image, volume, or network management API. See [01-architecture.md](01-architecture.md).

## Upload validation

Packages, plugins, and map sources: extension allowlist, size cap, path sanitization against traversal.

## Dependency security checks

CI audits the checked-in Python and UI dependency lockfiles before running tests or building the UI. When an audit fails, update the affected dependency to a patched compatible release and regenerate its lockfile; do not skip the audit step.

## Federation

Server-to-server TAK federation is configured in `templates/CoreConfig.tpl` (ports 9000–9002, mutual TLS). The ports are published by default in `docker-compose.yml`, but actual federation requires a mutual certificate exchange with the other TAK server — see the `<federation>` block in `templates/CoreConfig.tpl`.

## Reporting a vulnerability

See the repo root [SECURITY.md](../SECURITY.md) — report privately via GitHub Security Advisories, not a public issue.
