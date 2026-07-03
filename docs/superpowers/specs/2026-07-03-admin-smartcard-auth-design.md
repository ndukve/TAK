# Admin Panel Smart Card (CAC/PIV) Authentication — Design

## Purpose

Add an optional physical smart-card / hardware-token login path for TAK
admin panel accounts, for cases where a superadmin/admin can't access the
physical server machine but still needs strong, phishing-resistant
authentication into the web admin panel. Password login remains fully
functional and is the default; smart card is additive, not a replacement,
in this iteration. The long-term goal (out of scope here) is for cert-based
login to eventually become the default/mandatory path with zero extra
clicks — this design is built so that end state is a natural extension, not
a rework.

## Non-goals

- Making smart card mandatory (future work).
- WebAuthn/FIDO2 USB keys — this design is specifically for CAC/PIV-style
  smart cards authenticated via mutual TLS client certificates, not the
  WebAuthn browser API.
- Any change to TAK Server's own client certificate model (8089 mTLS for
  CoT streams, or Marti's own cert-based web login) — this is a completely
  separate CA and code path from that.

## Architecture

A **separate, admin-panel-only CA** (distinct from `templates/`'s existing
TAK client CA) is generated during install and used exclusively to sign
admin-account client certificates. `admin/nginx/nginx.conf`'s existing
`admin_proxy` server block gains:

```nginx
ssl_client_certificate /etc/nginx/ssl/admin-ca.pem;
ssl_verify_client optional;
```

`ssl_verify_client optional` requests a client certificate on every TLS
handshake but does not require one — connections without a cert (or with
one that fails verification) proceed normally to the password-login flow.
nginx forwards the verification outcome to FastAPI via headers:

```nginx
proxy_set_header X-SSL-Client-Verify  $ssl_client_verify;
proxy_set_header X-SSL-Client-Fingerprint $ssl_client_fingerprint;
```

Because the `admin` FastAPI container has no published port in
`docker-compose.yml` (only reachable through `admin_proxy`), and
`proxy_set_header` always overwrites rather than appends, these headers
cannot be spoofed by an external client — nginx is the sole path to
FastAPI and always sets its own values.

## Data model

New nullable column on `admin_users`:

```python
cert_fingerprint: Mapped[str | None] = mapped_column(String(64), nullable=True, unique=True)
```

This repo has no Alembic; schema evolution follows the existing lightweight
pattern already used for env-var backfills in `update.sh` (idempotent
check-and-add, not a versioned migration tool). A small idempotent
`ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS cert_fingerprint VARCHAR(64)`
runs once during the FastAPI `lifespan` startup, alongside the existing
`Base.metadata.create_all` call.

## Cert issuance

When an admin account is created, or when a superadmin explicitly
(re)generates a cert for an existing account, the backend:

1. Generates a keypair + CSR for that account (CN = account username or a
   generated UID — CN must be unique and stable).
2. Signs it with the admin-CA. The existing `admin_ssl` volume is owned by
   `admin_proxy`'s own entrypoint (which generates the server's self-signed
   TLS cert/key into it) — the admin-CA material should not be written
   there by a different container. Instead, a new `admin_ca` volume holds
   the CA's private key + public cert, mounted read-write into `admin`
   (which generates the CA once on first boot and signs certs into it) and
   read-only into `admin_proxy` (which only needs the CA's **public** cert
   for `ssl_client_certificate` — never the private key).
3. Computes the SHA-256 fingerprint of the issued certificate and stores it
   on `AdminUser.cert_fingerprint`.
4. Returns the cert + private key (PEM, or a password-protected PKCS12
   bundle — implementation detail for the plan) to the caller **once**.
   The plaintext private key is never persisted server-side beyond this
   single response; only the fingerprint is stored, matching how passwords
   are hashed rather than stored.

The admin then loads that cert onto their physical smart card or USB token
via OS-level tools — this step is explicitly out of scope for our system;
we only produce the cert material.

## Login flow

On mount, the login page calls a new endpoint, e.g. `GET /auth/cert-check`.
The backend reads `X-SSL-Client-Verify` / `X-SSL-Client-Fingerprint` from
the request (set by nginx). If verify is `SUCCESS` and the fingerprint
matches an **active** `AdminUser.cert_fingerprint`, the endpoint issues a
JWT access token (and refresh cookie) exactly as `/auth/login` does today,
and the frontend redirects straight to the dashboard — the password form is
never shown.

If there's no cert, verification failed, or the fingerprint doesn't match
any active account, the endpoint returns a neutral "no cert" response and
the frontend falls back to rendering the password form unchanged. This
fallback path is indistinguishable from "no card present" regardless of
the underlying reason (invalid cert, revoked fingerprint, expired cert,
etc.) — no error is surfaced, to avoid leaking any information about
cert presence/validity to an unauthenticated party.

## Shell-elevate integration

`POST /auth/shell-elevate` currently requires re-entering the account
password. It gains an alternate path: if the same cert-check headers
indicate a verified cert matching the currently authenticated user's
`cert_fingerprint`, the ticket is issued without requiring the password
field. The existing password-based path is unchanged for accounts without
a registered cert, or when no card is presented at elevate time.

## Revocation

Superadmins get a "Revoke Smart Card" action per admin account (in the
existing admin-users management UI) that sets `cert_fingerprint` back to
`NULL`. Because cert-check matches against the stored fingerprint (not
just "is this cert validly signed by our CA"), revocation is immediate and
requires no CRL distribution — a revoked cert simply no longer matches any
account, even though the certificate itself remains cryptographically
valid until its natural expiry.

## Backward compatibility

Existing admin accounts (created before this feature) have
`cert_fingerprint = NULL` by default and are entirely unaffected — they
continue to see and use the password form exactly as today. A superadmin
can generate a cert for such an account at any time via the same
regeneration action described under Cert issuance.

## Testing

- Generate a test cert via the new issuance path, import it into a
  browser's own certificate store (simulates a smart card without needing
  physical hardware for dev/test), confirm silent cert-check login.
- Confirm a second browser/profile without the cert still gets the normal
  password form.
- Revoke the fingerprint via the admin UI, confirm the same cert no longer
  logs in silently and the account falls back to password.
- Confirm shell-elevate accepts the cert path when present, and still
  accepts password when it isn't.
- Confirm accounts with `cert_fingerprint = NULL` (pre-existing accounts)
  are entirely unaffected by any of the above.
