# TAK Admin Panel — Design Spec
**Date:** 2026-06-25

## Overview

A web-based administration panel for the standalone TAK server. Replaces shell scripts and Makefile targets with a browser UI while keeping all existing CLI workflows intact. Implemented as a single new Docker service (`admin`) that serves both the REST API and the built React frontend.

---

## Architecture

### Services

One new container added to `docker-compose.yml`:

```
admin (:8889)
├── FastAPI (Python)           REST API + static file serving
├── PostgreSQL                 Uses existing takdb container, separate admin database
└── React + Vite + Tailwind    Built static files served by FastAPI
```

### Volumes / mounts

| Mount | Mode | Purpose |
|---|---|---|
| `/var/run/docker.sock` | rw | Container health, log streaming, docker exec for TAK ops |
| `takserver_data` | ro | Read packages, plugins, maps |
| `tak_plugins` | rw | Upload APKs |

### Database

New `admin` database on the existing `takdb` PostgreSQL instance.

Tables:
- `admin_users` — id, username, password_hash, role, created_by, created_at, is_active
- `refresh_tokens` — id, user_id, token_hash, expires_at, revoked
- `audit_log` — id, user_id, action, detail, timestamp
- `invite_links` — id, created_by, token_hash, role, expires_at, used_at

---

## Roles

| Role | Permissions |
|---|---|
| `superadmin` | Full access: all tabs + shell + admin user management |
| `admin` | Users, packages, plugins, maps, health, logs — no shell, no admin-user management |
| `readonly` | Health/status dashboard only |

---

## Frontend

Stack: React 18 + Vite + TypeScript + Tailwind CSS + shadcn/ui + TanStack Router (same as `deploy/uiv2`).

Built static files are served from FastAPI at `/`.

### Routes

| Route | Roles | Description |
|---|---|---|
| `/login` | public | Login form |
| `/` | all | Dashboard — service health cards, uptime, active connections |
| `/users` | admin+ | List TAK users, enable/disable/delete per row |
| `/users/new` | admin+ | Cert generation wizard: gen-device-cert → make-package → enable-user |
| `/packages` | admin+ | List `.zip` packages, download link + QR code per user |
| `/plugins` | admin+ | List APKs, drag-and-drop upload |
| `/maps` | admin+ | List XML map sources by provider, upload new XML |
| `/logs` | admin+ | Live log tail via WebSocket, service selector dropdown |
| `/shell` | superadmin | xterm.js terminal — requires re-authentication before opening |
| `/admin-users` | superadmin | List admin accounts with role badges |
| `/admin-users/new` | superadmin | Create admin account or generate invite link (24h, single-use) |

---

## Backend API

FastAPI application. All routes (except `/auth/*`) require `Authorization: Bearer <jwt>`.

### Auth

```
POST /auth/login          {username, password} → {access_token} + refresh cookie
POST /auth/refresh        (refresh cookie)     → {access_token}
POST /auth/logout         revokes refresh token
POST /auth/shell-elevate  {password}           → {shell_ticket} (5 min, single-use)
```

### TAK Users (docker exec into takserver_config)

```
GET    /api/users                  list all certs
POST   /api/users/gen-cert         {username} → runs gen_client_cert.sh
POST   /api/users/make-package     {username} → runs make_pkg_zip.sh
POST   /api/users/enable           {username} → runs enable_user.sh
POST   /api/users/disable          {username} → runs UserManager.jar certmod disable
DELETE /api/users/{username}       runs delete_user.sh
```

### Health

```
GET /api/health           container states + port reachability snapshot
WS  /api/health/stream    live Docker container events
```

### Packages / Plugins / Maps

```
GET  /api/packages         list clientpkgs/*.zip
GET  /api/plugins          list plugins/*.apk
POST /api/plugins          multipart upload → plugins/
GET  /api/maps             list maps/**/*.xml grouped by provider
POST /api/maps             multipart upload → maps/{provider}/
```

### Logs

```
WS /api/logs?service=<name>   streams docker logs --follow for chosen service
```

### Shell

```
POST /api/shell/ticket    validates shell_ticket → returns one-time WS token
WS   /api/shell/ws?t=...  opens bash in takserver_config
```

### Admin Users

```
GET    /api/admin-users           list accounts
POST   /api/admin-users           create account
PATCH  /api/admin-users/{id}      change role or reset password
DELETE /api/admin-users/{id}      deactivate (soft delete)
POST   /api/admin-users/invite    generate invite link
```

---

## Security

- **Passwords:** bcrypt-hashed, minimum 12 characters enforced
- **Sessions:** JWT access token (15 min) + httpOnly refresh cookie (7 days)
- **Shell elevation:** re-enter admin password → 5-min shell ticket, single WebSocket session
- **Login rate limiting:** 5 failed attempts → 15-minute lockout (stored in postgres)
- **Docker exec:** scoped to `takserver_config` container only, no arbitrary container exec
- **Audit log:** every write action recorded (user, action, timestamp, detail)
- **Invite links:** single-use, 24-hour expiry, hashed in DB
- **Network binding:** admin container binds to `127.0.0.1:8889` by default — expose only via NetBird or reverse proxy

---

## docker-compose addition

```yaml
admin:
  build: ./admin
  env_file: takserver.env
  environment:
    ADMIN_DB_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@takdb:5432/admin
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - takserver_data:/opt/tak/data:ro
    - tak_plugins:/opt/tak/plugins:rw
  ports:
    - "127.0.0.1:8889:8889"
  networks:
    - taknet
  depends_on:
    takdb:
      condition: service_healthy
    takserver_initialization:
      condition: service_completed_successfully
  restart: unless-stopped
```

New env vars to add to `takserver.env.example`:
```
ADMIN_SECRET_KEY=              # JWT signing secret (generated by install.sh)
ADMIN_FIRST_USER=admin         # username created on first boot
ADMIN_FIRST_PASS=              # generated by install.sh, printed once
```

---

## Directory structure

```
admin/
├── Dockerfile
├── api/
│   ├── main.py
│   ├── auth.py
│   ├── users.py
│   ├── health.py
│   ├── logs.py
│   ├── shell.py
│   ├── admin_users.py
│   ├── packages.py
│   ├── db.py
│   └── models.py
└── ui/
    ├── package.json
    ├── vite.config.ts
    └── src/
        ├── routes/
        │   ├── login.tsx
        │   ├── index.tsx          (dashboard)
        │   ├── users.tsx
        │   ├── users.new.tsx
        │   ├── packages.tsx
        │   ├── plugins.tsx
        │   ├── maps.tsx
        │   ├── logs.tsx
        │   ├── shell.tsx
        │   ├── admin-users.tsx
        │   └── admin-users.new.tsx
        └── components/
```

---

## First-boot behaviour

On first start, if the `admin` database has no users, the container:
1. Creates the `admin` database and runs migrations (SQLAlchemy/Alembic)
2. Creates the first `superadmin` account from `ADMIN_FIRST_USER` / `ADMIN_FIRST_PASS`
3. Prints credentials to container logs (one time only)
