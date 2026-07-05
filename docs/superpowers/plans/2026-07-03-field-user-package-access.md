# Field User Package Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the unauthenticated public package server (port 8888) and replace it with per-user, authenticated, ownership-scoped package/map access through the existing admin panel, plus a break-glass CLI fallback for when the panel itself is down.

**Architecture:** A new `field` role on the existing `admin_users` table (with a new `owned_callsign` column) sees a cut-down admin panel nav (Packages + Maps only). Package listing/download endpoints filter results to `{owned_callsign}-*` files when the caller is `field`; maps stay unfiltered. A field account is auto-created-or-reused whenever a package is generated through the web UI. `scripts/serve_packages.py` and the `pkg_server` compose service are deleted entirely.

**Tech Stack:** FastAPI + SQLAlchemy async (Python), React + TanStack Router + Tailwind (TypeScript), Docker Compose, bash.

## Global Constraints

- No automated test framework exists in this codebase (`admin/requirements.txt` has no pytest, no `tests/` directory anywhere under `admin/`). Every existing feature in this repo has been verified manually (curl + docker exec + browser), never with an automated suite. Per "follow established patterns," this plan uses the same manual-verification approach — each task's verification step is a runnable curl/docker command with the exact expected output, not a pytest file.
- Callsign suffix convention: TAK usernames end in `-ATAK`, `-WinTAK`, or `-iTAK` (enforced by `admin/api/users.py`'s `_NEW_USERNAME_RE`). "Base callsign" always means that suffix stripped.
- `admin_users.role` is a free-text `String(16)` column — no enum, no DB-level constraint. Valid values today: `superadmin`, `admin`, `readonly`. This plan adds `field` as a fourth value, checked only in application code (`require_role(...)` calls), same as the existing three.
- Schema evolution in this repo is idempotent ad-hoc SQL run at startup (see `admin/api/main.py`'s `lifespan` calling `Base.metadata.create_all`, which only creates missing *tables*, never missing *columns*) — there is no Alembic. New columns are added via an idempotent `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` check, following the same pattern already used for env-var backfills in `update.sh`.
- The map XML files that actually exist today (40 files across `Bing/`, `Google/`, `ESRI/`, etc.) live in `packages/tak-maps/` on the host, currently bind-mounted only into the now-being-deleted `pkg_server` service. The admin panel's own `/api/maps` endpoint reads from a *different*, currently-empty location (`takserver_data` volume's `data/maps`). This plan fixes that mismatch as part of the work — the real maps must become visible through the admin panel, or field/admin users lose access to all 40 of them.

---

### Task 1: Add `owned_callsign` column and `field` role plumbing

**Files:**
- Modify: `admin/api/models.py:16-25` (`AdminUser` class)
- Modify: `admin/api/main.py:19-25` (`lifespan`)

**Interfaces:**
- Produces: `AdminUser.owned_callsign: str | None` — nullable, set only for `field`-role rows. Later tasks read/write this field directly on `AdminUser` instances.

- [ ] **Step 1: Add the column to the model**

Edit `admin/api/models.py`, inside the `AdminUser` class, add this line right after `role`:

```python
    owned_callsign: Mapped[str | None] = mapped_column(String(64), nullable=True)
```

- [ ] **Step 2: Add an idempotent migration in `lifespan`**

Edit `admin/api/main.py`. Add this import at the top alongside the existing ones:

```python
from sqlalchemy import text
```

Then change the `lifespan` function from:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    await ensure_database()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await _ensure_first_user()
    yield
```

to:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    await ensure_database()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(text(
            "ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS owned_callsign VARCHAR(64)"
        ))
    await _ensure_first_user()
    yield
```

- [ ] **Step 3: Verify syntax**

```bash
python3 -c "import ast; ast.parse(open('admin/api/models.py').read())" && echo "models.py: OK"
python3 -c "import ast; ast.parse(open('admin/api/main.py').read())" && echo "main.py: OK"
```

Expected: both print `OK`.

- [ ] **Step 4: Commit**

```bash
git add admin/api/models.py admin/api/main.py
git commit -m "feat: add owned_callsign column for field-role package scoping"
```

---

### Task 2: Fix the maps directory mismatch, real download endpoints in `packages.py`

**Files:**
- Modify: `admin/api/packages.py:1-19` (imports, constants)
- Modify: `admin/api/packages.py` (`list_packages`, add package download endpoint)
- Modify: `admin/api/packages.py` (`list_plugins`, add plugin download endpoint)
- Modify: `admin/api/packages.py` (`list_maps`, add map download endpoint, fix `MAPS_DIR`)
- Modify: `docker-compose.yml` (admin service volumes — bind-mount the real maps directory)

**Interfaces:**
- Consumes: `admin.deps.require_role`, `AdminUser` from Task 1 (`.role`, `.owned_callsign`)
- Produces: `GET /api/packages/{name}/download`, `GET /api/plugins/{filename}/download`, `GET /api/maps/{provider}/{filename}/download` — all stream the actual file bytes with `FileResponse`, replacing reliance on the now-deleted `PKG_SERVER_URL`.

This task also fixes a pre-existing bug: `packages.py`'s `MAPS_DIR` currently points at `/opt/tak/data/maps` (inside the `takserver_data` volume), but the 40 real map XML files live in the host directory `packages/tak-maps/`, which is currently only bind-mounted into the `pkg_server` service being deleted. Without this fix, deleting `pkg_server` would make every map invisible.

- [ ] **Step 1: Bind-mount the real maps directory into `admin`**

In `docker-compose.yml`, find the `admin` service's `volumes:` block (added in this session's earlier work, currently reading):

```yaml
    volumes:
      - takserver_data:/opt/tak/data:rw
      - tak_plugins:/opt/tak/plugins:rw
```

Change it to:

```yaml
    volumes:
      - takserver_data:/opt/tak/data:rw
      - tak_plugins:/opt/tak/plugins:rw
      - ./packages/tak-maps:/opt/tak/maps:rw
```

- [ ] **Step 2: Point `MAPS_DIR` at the same path, and add the role-based filtering helper**

In `admin/api/packages.py`, change:

```python
MAPS_DIR = os.path.join(TAK_DATA, "maps")  # takserver_data volume → /opt/tak/data/maps
```

to:

```python
MAPS_DIR = "/opt/tak/maps"  # host packages/tak-maps/ → bind-mounted read-write here
```

Then change the router's default role dependency and add a field-aware one. Replace:

```python
router = APIRouter(tags=["packages"])
_admin = require_role("admin", "superadmin")
```

with:

```python
from starlette.responses import FileResponse

router = APIRouter(tags=["packages"])
_admin = require_role("admin", "superadmin")
_admin_or_field = require_role("admin", "superadmin", "field")


def _base_callsign(filename: str) -> str:
    """Strip the trailing -ATAK/-WinTAK/-iTAK suffix. 'Alpha1-iTAK.zip' -> 'Alpha1'."""
    name = filename.rsplit(".", 1)[0]
    for suffix in ("-ATAK", "-WinTAK", "-iTAK"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name
```

- [ ] **Step 3: Filter package listing by role, add package download endpoint**

Replace the existing `list_packages` function:

```python
@router.get("/api/packages")
async def list_packages(_=Depends(_admin)):
    if not os.path.isdir(PKGS_DIR):
        return {"packages": []}
    files = sorted(f for f in os.listdir(PKGS_DIR) if f.endswith(".zip"))
    pkgs = []
    for f in files:
        entry = {"name": f.replace(".zip", ""), "filename": f, "size": _size(os.path.join(PKGS_DIR, f))}
        if PKG_SERVER_URL:
            entry["url"] = f"{PKG_SERVER_URL}/{f}"
        pkgs.append(entry)
    return {"packages": pkgs}
```

with:

```python
@router.get("/api/packages")
async def list_packages(actor=Depends(_admin_or_field)):
    if not os.path.isdir(PKGS_DIR):
        return {"packages": []}
    files = sorted(f for f in os.listdir(PKGS_DIR) if f.endswith(".zip"))
    if actor.role == "field":
        files = [f for f in files if _base_callsign(f) == actor.owned_callsign]
    return {"packages": [
        {"name": f.replace(".zip", ""), "filename": f, "size": _size(os.path.join(PKGS_DIR, f))}
        for f in files
    ]}


@router.get("/api/packages/{name}/download")
async def download_package(name: str, actor=Depends(_admin_or_field)):
    safe_name = os.path.basename(name)
    if actor.role == "field" and _base_callsign(safe_name) != actor.owned_callsign:
        raise HTTPException(status_code=404, detail="Package not found")
    path = os.path.join(PKGS_DIR, f"{safe_name}.zip")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Package not found")
    return FileResponse(path, filename=f"{safe_name}.zip", media_type="application/zip")
```

Also delete the now-unused `PKG_SERVER_URL` line near the top of the file (it read `PKG_SERVER_URL = os.environ.get("PKG_SERVER_URL", "").rstrip("/")` — remove it entirely, it's dead once `pkg_server` no longer exists).

- [ ] **Step 4: Add plugin download endpoint (admin/superadmin only — field never sees plugins)**

Add this new endpoint right after the existing `list_plugins` function:

```python
@router.get("/api/plugins/{filename}/download")
async def download_plugin(filename: str, _=Depends(_admin)):
    safe_name = os.path.basename(filename)
    path = os.path.join(PLUGINS_DIR, safe_name)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Plugin not found")
    return FileResponse(path, filename=safe_name)
```

- [ ] **Step 5: Allow `field` on map listing, add map download endpoint**

Replace:

```python
@router.get("/api/maps")
async def list_maps(_=Depends(_admin)):
```

with:

```python
@router.get("/api/maps")
async def list_maps(_=Depends(_admin_or_field)):
```

Then add this new endpoint right after `list_maps`:

```python
@router.get("/api/maps/{provider}/{filename}/download")
async def download_map(provider: str, filename: str, _=Depends(_admin_or_field)):
    safe_provider = os.path.basename(provider)
    safe_filename = os.path.basename(filename)
    path = os.path.join(MAPS_DIR, safe_provider, safe_filename)
    if not os.path.realpath(path).startswith(os.path.realpath(MAPS_DIR) + os.sep):
        raise HTTPException(status_code=403, detail="Invalid path")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Map not found")
    return FileResponse(path, filename=safe_filename, media_type="text/xml")
```

- [ ] **Step 6: Verify syntax**

```bash
python3 -c "import ast; ast.parse(open('admin/api/packages.py').read())" && echo "packages.py: OK"
python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" && echo "docker-compose.yml: valid YAML"
```

Expected: both print OK/valid.

- [ ] **Step 7: Commit**

```bash
git add admin/api/packages.py docker-compose.yml
git commit -m "fix: maps directory mismatch, add real download endpoints, scope packages to field role"
```

---

### Task 3: Auto-create-or-reuse field account on package generation

**Files:**
- Modify: `admin/api/users.py:1-20` (imports)
- Modify: `admin/api/users.py` (`make_package` function)

**Interfaces:**
- Consumes: `AdminUser` model + `owned_callsign` from Task 1, `pwd_ctx` and `write_audit` from `admin/api/deps.py` (already imported elsewhere in this file's sibling modules).
- Produces: `make_package` response gains fields `field_account_created: bool`, `field_account_password: str | None`, `field_username: str`. New endpoint `POST /api/users/create-field-login/{username}` (same response shape) for CLI-generated packages that never went through `make_package` — Task 5 wires a frontend button to this.

- [ ] **Step 1: Add needed imports**

In `admin/api/users.py`, add to the existing import block:

```python
import secrets
from sqlalchemy import select
from .models import AdminUser
from .deps import pwd_ctx
```

(The file already imports `require_role, write_audit` from `.deps` — add `pwd_ctx` to that same existing import line rather than a new one, i.e. change `from .deps import require_role, write_audit` to `from .deps import require_role, write_audit, pwd_ctx`.)

- [ ] **Step 2: Add the base-callsign helper**

Add this function near the top of the file, after `_validate_new_username`:

```python
def _base_callsign(username: str) -> str:
    for suffix in ("-ATAK", "-WinTAK", "-iTAK"):
        if username.endswith(suffix):
            return username[: -len(suffix)]
    return username
```

- [ ] **Step 3: Extract a shared create-or-reuse helper, wire it into `make_package`**

This helper is also used standalone in Step 4 below (for CLI-generated packages, which never go through `make_package`), so it's written as its own function rather than being inlined into `make_package` alone. Add this function near the top of the file, after `_base_callsign`:

```python
async def _ensure_field_account(db: AsyncSession, base: str, created_by: str) -> tuple[bool, str | None]:
    """Create a field-role account for this base callsign if one doesn't
    already exist. Returns (created, password) — password is None when an
    existing account was reused (nothing new to show)."""
    existing = await db.execute(
        select(AdminUser).where(AdminUser.role == "field", AdminUser.owned_callsign == base)
    )
    if existing.scalar_one_or_none() is not None:
        return False, None
    password = secrets.token_urlsafe(12)
    db.add(AdminUser(
        username=base,
        password_hash=pwd_ctx.hash(password),
        role="field",
        owned_callsign=base,
        created_by=created_by,
    ))
    await db.commit()
    return True, password
```

Replace:

```python
@router.post("/make-package", status_code=201)
async def make_package(body: UsernameRequest, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_new_username(body.username)
    code, out = await run_in_container(
        ["bash", "/opt/scripts/make_pkg_zip.sh"],
        env={"CLIENT_CERT_NAME": username, "TAK_SERVER_ADDRESS": SERVER_ADDR},
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=out)
    await write_audit(db, actor.id, "make_package", username)
    return {"status": "ok", "download_url": f"http://{SERVER_ADDR}:8888/{username}.zip"}
```

with:

```python
@router.post("/make-package", status_code=201)
async def make_package(body: UsernameRequest, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_new_username(body.username)
    code, out = await run_in_container(
        ["bash", "/opt/scripts/make_pkg_zip.sh"],
        env={"CLIENT_CERT_NAME": username, "TAK_SERVER_ADDRESS": SERVER_ADDR},
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=out)
    await write_audit(db, actor.id, "make_package", username)

    base = _base_callsign(username)
    created, password = await _ensure_field_account(db, base, actor.username)
    if created:
        await write_audit(db, actor.id, "create_field_account", base)

    return {
        "status": "ok",
        "package_name": username,
        "field_account_created": created,
        "field_account_password": password,
        "field_username": base,
    }
```

- [ ] **Step 4: Add a manual creation endpoint for CLI-generated packages**

CLI-generated packages (`./generate_user.sh`, no admin-panel involvement) never hit `make_package`, so they never get a field account automatically. This endpoint lets a superadmin/admin create one after the fact for any package that already exists on disk, using the same shared helper.

Add this new endpoint right after `make_package`:

```python
@router.post("/create-field-login/{username}", status_code=201)
async def create_field_login(username: str, db: AsyncSession = Depends(get_db), actor=Depends(_admin)):
    username = _validate_username(username)
    if not os.path.isfile(os.path.join(CLIENTPKGS, f"{username}.zip")):
        raise HTTPException(status_code=404, detail="No package with that name exists")
    base = _base_callsign(username)
    created, password = await _ensure_field_account(db, base, actor.username)
    if created:
        await write_audit(db, actor.id, "create_field_account", base)
    return {"field_account_created": created, "field_account_password": password, "field_username": base}
```

- [ ] **Step 5: Verify syntax**

```bash
python3 -c "import ast; ast.parse(open('admin/api/users.py').read())" && echo "users.py: OK"
```

Expected: prints `OK`.

- [ ] **Step 6: Commit**

```bash
git add admin/api/users.py
git commit -m "feat: auto-create-or-reuse field account when generating a package"
```

---

### Task 4: Filter `field` accounts out of the Admin Users listing by default

**Files:**
- Modify: `admin/api/admin_users.py` (`list_users`)

**Interfaces:**
- Produces: `GET /api/admin-users?include_field=true` query param. Default (no param, or `false`) excludes `role='field'` rows.

- [ ] **Step 1: Add the filter**

Replace:

```python
@router.get("")
async def list_users(db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    result = await db.execute(select(AdminUser))
    users = result.scalars().all()
    return {"users": [
        {"id": u.id, "username": u.username, "role": u.role, "is_active": u.is_active, "created_at": u.created_at}
        for u in users
    ]}
```

with:

```python
@router.get("")
async def list_users(include_field: bool = False, db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    query = select(AdminUser)
    if not include_field:
        query = query.where(AdminUser.role != "field")
    result = await db.execute(query)
    users = result.scalars().all()
    return {"users": [
        {"id": u.id, "username": u.username, "role": u.role, "is_active": u.is_active, "created_at": u.created_at}
        for u in users
    ]}
```

- [ ] **Step 2: Verify syntax**

```bash
python3 -c "import ast; ast.parse(open('admin/api/admin_users.py').read())" && echo "admin_users.py: OK"
```

Expected: prints `OK`.

- [ ] **Step 3: Commit**

```bash
git add admin/api/admin_users.py
git commit -m "feat: hide field accounts from Admin Users listing by default"
```

---

### Task 5: Frontend — role-based nav, field-friendly Packages page, downloads

**Files:**
- Modify: `admin/ui/src/components/Layout.tsx` (nav items)
- Modify: `admin/ui/src/routes/packages.tsx` (download link, field-account password display)
- Modify: `admin/ui/src/routes/maps.tsx` (add download link — currently has none)
- Modify: `admin/ui/src/routes/admin-users.tsx` (include-field toggle)

**Interfaces:**
- Consumes: `role` from `useAuth()` (already exists, `admin/ui/src/store/auth.ts`)

- [ ] **Step 1: Cut down the nav for `field` role**

In `admin/ui/src/components/Layout.tsx`, replace:

```tsx
const navItems = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/users', label: 'Users', icon: Users },
  { to: '/packages', label: 'Packages', icon: Package },
  { to: '/plugins', label: 'Plugins', icon: Puzzle },
  { to: '/maps', label: 'Maps', icon: Map },
  { to: '/logs', label: 'Logs', icon: ScrollText },
]
```

with:

```tsx
const navItems = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/users', label: 'Users', icon: Users },
  { to: '/packages', label: 'Packages', icon: Package },
  { to: '/plugins', label: 'Plugins', icon: Puzzle },
  { to: '/maps', label: 'Maps', icon: Map },
  { to: '/logs', label: 'Logs', icon: ScrollText },
]

const fieldItems = [
  { to: '/packages', label: 'Packages', icon: Package },
  { to: '/maps', label: 'Maps', icon: Map },
]
```

Then find this line further down in the same file:

```tsx
  const items = role === 'superadmin' ? [...navItems, ...superAdminItems] : navItems
```

and replace it with:

```tsx
  const items = role === 'field' ? fieldItems
    : role === 'superadmin' ? [...navItems, ...superAdminItems]
    : navItems
```

- [ ] **Step 2: Route-guard Packages/Maps/Dashboard/Users/Plugins/Logs against `field`**

Every route already has a `beforeLoad` checking `token`. `field` accounts must not be able to navigate directly to `/users`, `/plugins`, `/logs`, or `/` by typing the URL even though the nav hides those links. Backend `require_role` already 403s the underlying API calls, but the page itself would still render an empty/broken shell. Add a role check to each of these five routes' existing `beforeLoad`.

For `admin/ui/src/routes/users.tsx`, find:

```tsx
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
```

and change to:

```tsx
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role === 'field') throw redirect({ to: '/packages' })
  },
```

Apply the identical change (same before/after text) to `admin/ui/src/routes/plugins.tsx`, `admin/ui/src/routes/logs.tsx`, and `admin/ui/src/routes/index.tsx` (the Dashboard route — check its exact `beforeLoad` matches this same `{ token }`-only pattern before editing; if it's phrased slightly differently, apply the same `if (role === 'field') throw redirect({ to: '/packages' })` addition after the existing token check).

- [ ] **Step 3: Real download links + field-account password reveal in Packages page**

In `admin/ui/src/routes/packages.tsx`, the `Package` interface currently has an optional `url` field used for the download link (`p.url`). Since downloads now come from our own new endpoint (Task 2) instead of an external URL, replace every `p.url` / `selected.url` usage with a constructed link.

Replace:

```tsx
interface Package {
  name: string
  filename: string
  size: string
  url?: string
}
```

with:

```tsx
interface Package {
  name: string
  filename: string
  size: string
}
```

Then replace both occurrences of:

```tsx
                        {p.url && (
                          <a
                            href={p.url}
                            onClick={e => e.stopPropagation()}
                            download
                            className="p-1.5 rounded hover:bg-zinc-800 text-blue-400"
                            title="Download"
                          >
                            <Download size={14} />
                          </a>
                        )}
```

with:

```tsx
                        <a
                          href={`/api/packages/${encodeURIComponent(p.name)}/download`}
                          onClick={e => e.stopPropagation()}
                          download
                          className="p-1.5 rounded hover:bg-zinc-800 text-blue-400"
                          title="Download"
                        >
                          <Download size={14} />
                        </a>
```

And replace:

```tsx
                {selected.url && (
                  <a href={selected.url} download className="text-xs text-blue-400 hover:underline break-all text-center">
                    {selected.url}
                  </a>
                )}
```

with:

```tsx
                <a href={`/api/packages/${encodeURIComponent(selected.name)}/download`} download className="text-xs text-blue-400 hover:underline break-all text-center">
                  Download
                </a>
```

- [ ] **Step 4: "Create field login" button for CLI-generated packages**

CLI-generated packages (via `./generate_user.sh`) never went through `make_package`, so they have no field login yet. This button (backed by Task 3's `create-field-login` endpoint) lets a superadmin/admin create one after the fact for any package selected in this detail panel. Add this state near the top of `PackagesPage`:

```tsx
  const [fieldResult, setFieldResult] = useState<{ username: string; password: string | null; created: boolean } | null>(null)

  async function handleCreateFieldLogin(pkg: Package) {
    try {
      const res = await apiJson<any>(`/api/users/create-field-login/${encodeURIComponent(pkg.name)}`, { method: 'POST' })
      setFieldResult({ username: res.field_username, password: res.field_account_password, created: res.field_account_created })
    } catch (e: any) {
      toast.error(e.message)
    }
  }
```

Add a button in the detail panel, right after the existing download link (inside the `{selected ? (...) : (...)}` block):

```tsx
                <button
                  onClick={() => handleCreateFieldLogin(selected)}
                  className="text-xs px-3 py-1.5 rounded bg-zinc-800 hover:bg-zinc-700 text-zinc-300"
                >
                  Create field login
                </button>
                {fieldResult && (
                  <div className="p-2 rounded border border-yellow-700/50 bg-yellow-900/20 text-xs text-left space-y-1 w-full">
                    {fieldResult.created ? (
                      <>
                        <p className="text-yellow-200">Field login created — shown once:</p>
                        <p className="font-mono">user: {fieldResult.username}</p>
                        <p className="font-mono">pass: {fieldResult.password}</p>
                      </>
                    ) : (
                      <p className="text-zinc-400">Login already exists for "{fieldResult.username}" — no new password.</p>
                    )}
                  </div>
                )}
```

- [ ] **Step 5: Show the field-account password once, when a superadmin/admin generates a package via the Users page**

This surfaces the `field_account_created`/`field_account_password` fields added in Task 3. In `admin/ui/src/routes/users.tsx`, the `NewUserModal`'s `handleCreate` function currently does:

```tsx
      setStep('make-package')
      const pkg = await apiJson<any>('/api/users/make-package', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      if (pkg.download_url) setDownloadUrl(pkg.download_url)
```

Replace those three lines with:

```tsx
      setStep('make-package')
      const pkg = await apiJson<any>('/api/users/make-package', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      setDownloadUrl(`/api/packages/${encodeURIComponent(username)}/download`)
      if (pkg.field_account_created) {
        setFieldAccount({ username: pkg.field_username, password: pkg.field_account_password })
      }
```

Add the new state near the top of `NewUserModal`, alongside the existing `downloadUrl` state:

```tsx
  const [fieldAccount, setFieldAccount] = useState<{ username: string; password: string } | null>(null)
```

And in the `'done'` step's JSX, right after the existing download link block, add:

```tsx
            {fieldAccount && (
              <div className="p-3 rounded-lg border border-yellow-700/50 bg-yellow-900/20 text-sm space-y-1">
                <p className="text-yellow-200">Field login created — shown once, save it now:</p>
                <p className="font-mono text-zinc-200">user: {fieldAccount.username}</p>
                <p className="font-mono text-zinc-200">pass: {fieldAccount.password}</p>
              </div>
            )}
```

- [ ] **Step 6: Add download links to the Maps page (currently has none)**

In `admin/ui/src/routes/maps.tsx`, add `Download` to the existing lucide-react import:

```tsx
import { Trash2, Upload, Copy, Check, Download } from 'lucide-react'
```

Then in the table row's actions cell, find:

```tsx
                  <td className="px-4 py-3">
                    <div className="flex justify-end">
                      <button
                        onClick={() => handleDelete(m)}
                        className="p-1.5 rounded hover:bg-zinc-800 text-red-400"
                        title="Delete"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </td>
```

and replace with:

```tsx
                  <td className="px-4 py-3">
                    <div className="flex justify-end gap-1">
                      <a
                        href={`/api/maps/${encodeURIComponent(m.provider)}/${encodeURIComponent(m.filename)}/download`}
                        download
                        className="p-1.5 rounded hover:bg-zinc-800 text-blue-400"
                        title="Download"
                      >
                        <Download size={14} />
                      </a>
                      <button
                        onClick={() => handleDelete(m)}
                        className="p-1.5 rounded hover:bg-zinc-800 text-red-400"
                        title="Delete"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </td>
```

Note: the Delete button should only render for admin/superadmin in practice (field accounts never see this page's upload/delete UI in a meaningful way since their nav routes them to `/packages` and `/maps` only — the backend still 403s a `field` token hitting delete, so this is UI polish, not a security boundary).

- [ ] **Step 7: Add include-field toggle to Admin Users page**

In `admin/ui/src/routes/admin-users.tsx`, find the `load` function (it calls `apiJson<{ users: AdminUser[] }>('/api/admin-users')`) and add a checkbox state that toggles the query param. Add near the top of `AdminUsersPage`'s component body:

```tsx
  const [showField, setShowField] = useState(false)
```

Change the load call from:

```tsx
      const data = await apiJson<{ users: AdminUser[] }>('/api/admin-users')
```

to:

```tsx
      const data = await apiJson<{ users: AdminUser[] }>(`/api/admin-users?include_field=${showField}`)
```

Add `showField` to that effect's dependency array so toggling it re-fetches, and add a checkbox in the page header:

```tsx
          <label className="flex items-center gap-2 text-sm text-zinc-400">
            <input type="checkbox" checked={showField} onChange={e => setShowField(e.target.checked)} />
            Show field accounts
          </label>
```

(Place this checkbox in the same header row as the existing "New Admin User" button, adjust exact JSX placement to fit the existing layout.)

- [ ] **Step 8: Commit**

```bash
git add admin/ui/src/components/Layout.tsx admin/ui/src/routes/packages.tsx admin/ui/src/routes/maps.tsx admin/ui/src/routes/admin-users.tsx admin/ui/src/routes/users.tsx admin/ui/src/routes/plugins.tsx admin/ui/src/routes/logs.tsx admin/ui/src/routes/index.tsx
git commit -m "feat: field-role nav, real download links, field account password reveal"
```

---

### Task 6: Mobile-responsive layout for field-facing pages

**Files:**
- Modify: `admin/ui/src/components/Layout.tsx` (sidebar → collapsible on narrow viewports)
- Modify: `admin/ui/src/routes/packages.tsx` (table overflow wrapper)
- Modify: `admin/ui/src/routes/maps.tsx` (table overflow wrapper)

**Interfaces:** none — purely presentational, no new props/functions consumed elsewhere.

`Layout.tsx`'s sidebar is a fixed `w-56` (224px) column with no responsive collapse — on a typical 375-414px phone viewport that's over half the screen permanently occupied by navigation, which is the single biggest mobile-usability problem for the `field` role this whole feature is built for. The tables in Packages and Maps have no horizontal-scroll containment, so a phone-width viewport can end up with a broken, edge-clipped table instead of a clean scrollable one.

- [ ] **Step 1: Make the sidebar collapsible below the `md` breakpoint**

In `admin/ui/src/components/Layout.tsx`, add `useState` to the existing React import if not already imported (check the top of the file — it currently imports `{ useState }` already for `ChangePasswordModal`'s local state, so this is already available at module scope; add a new state hook inside the `Layout` function itself).

Find:

```tsx
export function Layout({ children }: { children: React.ReactNode }) {
  const { role, clear } = useAuth()
  const navigate = useNavigate()
  const routerState = useRouterState()
  const current = routerState.location.pathname
  const [showChangePw, setShowChangePw] = useState(false)
```

and add a new state variable right after `showChangePw`:

```tsx
  const [sidebarOpen, setSidebarOpen] = useState(false)
```

Find the `<aside>` element:

```tsx
      <aside className="w-56 flex-shrink-0 border-r border-zinc-800 flex flex-col">
```

and replace it with a version that's hidden off-canvas on narrow screens and toggleable:

```tsx
      <aside className={cn(
        'w-56 flex-shrink-0 border-r border-zinc-800 flex flex-col',
        'fixed inset-y-0 left-0 z-40 bg-zinc-950 transition-transform md:relative md:translate-x-0',
        sidebarOpen ? 'translate-x-0' : '-translate-x-full'
      )}>
```

Add a hamburger toggle button and a backdrop, right after the opening `<div className="flex h-screen bg-zinc-950 text-zinc-100">` line:

```tsx
      <button
        onClick={() => setSidebarOpen(v => !v)}
        className="md:hidden fixed top-3 left-3 z-50 p-2 rounded-md bg-zinc-900 border border-zinc-800 text-zinc-300"
        aria-label="Toggle menu"
      >
        <Menu size={18} />
      </button>
      {sidebarOpen && (
        <div className="md:hidden fixed inset-0 bg-black/50 z-30" onClick={() => setSidebarOpen(false)} />
      )}
```

Add `Menu` to the existing lucide-react import at the top of the file (it currently imports `LayoutDashboard, Users, Package, Puzzle, Map, ScrollText, Terminal, ShieldUser, LogOut, KeyRound` — add `Menu` to that same list).

Finally, so the hamburger button doesn't get permanently covered by the fixed sidebar's own content on small screens, close the sidebar automatically after a nav link is clicked. Find the `<Link>` element inside the `nav`:

```tsx
            <Link
              key={to}
              to={to}
              className={cn(
```

and add an `onClick` right before the `className` prop:

```tsx
            <Link
              key={to}
              to={to}
              onClick={() => setSidebarOpen(false)}
              className={cn(
```

- [ ] **Step 2: Add top padding to `<main>` so content doesn't sit under the fixed hamburger button on mobile**

Find:

```tsx
      <main className="flex-1 overflow-auto">{children}</main>
```

and replace with:

```tsx
      <main className="flex-1 overflow-auto pt-14 md:pt-0">{children}</main>
```

- [ ] **Step 3: Wrap the Packages table in a horizontal-scroll container**

In `admin/ui/src/routes/packages.tsx`, find:

```tsx
          <div className="lg:col-span-2 rounded-lg border border-zinc-800 overflow-hidden">
            <table className="w-full text-sm">
```

and replace with:

```tsx
          <div className="lg:col-span-2 rounded-lg border border-zinc-800 overflow-x-auto">
            <table className="w-full text-sm min-w-[480px]">
```

- [ ] **Step 4: Wrap the Maps table in a horizontal-scroll container**

In `admin/ui/src/routes/maps.tsx`, find:

```tsx
        <div className="rounded-lg border border-zinc-800 overflow-hidden">
          <table className="w-full text-sm">
```

and replace with:

```tsx
        <div className="rounded-lg border border-zinc-800 overflow-x-auto">
          <table className="w-full text-sm min-w-[600px]">
```

- [ ] **Step 5: Verify by hand at phone width**

Start the dev server if not already running (`cd admin/ui && pnpm dev`), open the app in a browser, switch dev tools to device emulation at 375×667 (iPhone SE), and check:
- Login page: form is fully visible, no horizontal scroll.
- Any admin-panel page: hamburger button visible top-left, sidebar hidden by default, tapping it slides the sidebar in over a dark backdrop, tapping a nav link or the backdrop closes it.
- Packages / Maps pages: table scrolls horizontally within its own bordered box if content is wider than the viewport — the page itself does not scroll horizontally.

- [ ] **Step 6: Commit**

```bash
git add admin/ui/src/components/Layout.tsx admin/ui/src/routes/packages.tsx admin/ui/src/routes/maps.tsx
git commit -m "feat: mobile-responsive sidebar and tables for field-facing pages"
```

---

### Task 7: Retire `pkg_server` and `scripts/serve_packages.py`

**Files:**
- Modify: `docker-compose.yml` (remove `pkg_server` service)
- Delete: `scripts/serve_packages.py`
- Modify: `takserver.env.example` (remove `PKG_SERVER_PASS`, if present)

**Interfaces:** none — this is pure removal, no other task depends on `pkg_server` after Task 2 added real download endpoints.

- [ ] **Step 1: Remove the `pkg_server` service block**

In `docker-compose.yml`, delete this entire block:

```yaml
  # ── Package download server (port 8888) ────────────────────────────────────
  pkg_server:
    image: python:3.11-slim
    command: ["python3", "/srv/serve_packages.py"]
    environment:
      PKG_SERVER_PASS: ${PKG_SERVER_PASS:-}
    volumes:
      - takserver_data:/opt/tak/data:ro
      - ./packages/tak-maps:/opt/tak/maps:ro
      - ./scripts/serve_packages.py:/srv/serve_packages.py:ro
    working_dir: /opt/tak/data
    ports:
      - "8888:8888"
    networks:
      - taknet
    restart: unless-stopped
```

- [ ] **Step 2: Delete the script**

```bash
rm scripts/serve_packages.py
```

- [ ] **Step 3: Remove `PKG_SERVER_PASS` from the env example, if present**

```bash
grep -n "PKG_SERVER_PASS" takserver.env.example
```

If it prints a match, remove that line (and the comment line above it, if it's a dedicated one-line comment for this var only) from `takserver.env.example` with the Edit tool.

- [ ] **Step 4: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" && echo "docker-compose.yml: valid YAML"
grep -c pkg_server docker-compose.yml
```

Expected: first line prints `valid YAML`; second line prints `0` (no remaining references).

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yml takserver.env.example
git rm scripts/serve_packages.py
git commit -m "remove: retire public pkg_server, packages now served through the authenticated admin panel"
```

---

### Task 8: Break-glass CLI fallback script

**Files:**
- Create: `get_package.sh`

**Interfaces:** none — standalone script, no other task depends on it.

- [ ] **Step 1: Write the script**

```bash
cat > /home/ndukve/IdeaProjects/TAK/get_package.sh << 'SCRIPT'
#!/usr/bin/env bash
# Break-glass fallback: retrieve a package directly from the server, without
# needing the admin panel to be up. Requires SSH/shell access to the server
# itself — this is not a network service, nothing for an unauthenticated
# party to reach. Run with no argument to list what's available.
# Usage: ./get_package.sh [name]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

NAME="${1:-}"

if [ -z "$NAME" ]; then
    info "Available packages:"
    docker compose --env-file "$ENV_FILE" exec -T takserver_config \
        bash -c "ls /opt/tak/data/certs/files/clientpkgs/*.zip 2>/dev/null | xargs -n1 basename" \
        || warn "No packages found."
    exit 0
fi

DEST="./${NAME}.zip"
[ ! -f "$DEST" ] || fail "$DEST already exists in the current directory — remove it first or run this from elsewhere."

docker compose --env-file "$ENV_FILE" exec -T takserver_config \
    bash -c "cat /opt/tak/data/certs/files/clientpkgs/${NAME}.zip" > "$DEST" \
    || { rm -f "$DEST"; fail "Package '${NAME}' not found."; }

ok "Saved to ${DEST}"
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/get_package.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/get_package.sh && echo "get_package.sh: OK"
```

Expected: prints `OK`.

- [ ] **Step 3: Commit**

```bash
git add get_package.sh
git commit -m "feat: add get_package.sh break-glass CLI fallback for package retrieval"
```

---

### Task 8b: Interactive fallback CLI for packages + maps (`admin_fallback.sh`)

**Why:** `get_package.sh` (Task 8) is argument-based — the admin has to remember exact package names and flags. This adds a menu-driven wrapper covering the two things a field admin actually needs when the web UI is down: browsing/downloading packages, and browsing/downloading maps. Read-only — no create/delete/user-management, per explicit scope decision (packages + maps only, no destructive ops).

**Files:**
- Create: `admin_fallback.sh`

**Interfaces:** none — standalone script, no other task depends on it. Complements (does not replace) `get_package.sh`, which remains for non-interactive/scripted use.

**Key facts to use verbatim:**
- Packages live inside the `takserver_data` named Docker volume — reachable only via `docker compose exec takserver_config`, same as `get_package.sh` (already fixed for command-injection: pass the name as a positional arg to a single-quoted inner `bash -c` script, never interpolate directly into the command string).
- Maps live in a **host bind mount**, `packages/tak-maps/<provider>/<filename>`, relative to the repo root (`docker-compose.yml:147`: `./packages/tak-maps:/opt/tak/maps:rw`) — no `docker compose exec` needed, plain filesystem access.
- Path-traversal guard for map downloads must match the realpath-prefix pattern already used in `admin/api/packages.py`'s `download_map`/`delete_map` (resolve with `realpath -m`, verify the result still starts with the resolved `MAPS_DIR` + `/`).
- `read -rp` calls must tolerate Ctrl-D/EOF cleanly (exit 0) rather than aborting under `set -e`.
- Never use `fail` (defined in `scripts/_spinner.sh` as printing and calling `exit 1`) inside a menu-loop action — one failed lookup must return to the menu, not kill the whole session. Use `warn` for recoverable failures inside loop bodies.

- [ ] **Step 1: Write the script**

```bash
cat > /home/ndukve/IdeaProjects/TAK/admin_fallback.sh << 'SCRIPT'
#!/usr/bin/env bash
# Interactive break-glass fallback for the admin web UI: browse and download
# packages/maps from the terminal when the web UI is unavailable. Requires
# SSH/shell access to the server itself, same trust boundary as get_package.sh.
# Read-only: no create/delete, no user management.
# Usage: ./admin_fallback.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
MAPS_DIR="$SCRIPT_DIR/packages/tak-maps"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

list_packages() {
    docker compose --env-file "$ENV_FILE" exec -T takserver_config \
        bash -c "ls /opt/tak/data/certs/files/clientpkgs/*.zip 2>/dev/null | xargs -n1 basename" \
        || warn "No packages found."
}

download_package() {
    read -rp "Package name (without .zip): " NAME || { echo; return; }
    [ -n "$NAME" ] || { warn "No name given."; return; }
    local DEST="./${NAME}.zip"
    if [ -f "$DEST" ]; then
        warn "$DEST already exists in the current directory — remove it first or run this from elsewhere."
        return
    fi
    docker compose --env-file "$ENV_FILE" exec -T takserver_config \
        bash -c 'cat "/opt/tak/data/certs/files/clientpkgs/$1.zip"' -- "$NAME" > "$DEST" \
        || { rm -f "$DEST"; warn "Package '$NAME' not found."; return; }
    ok "Saved to $DEST"
}

list_maps() {
    if [ ! -d "$MAPS_DIR" ]; then
        warn "No maps directory found."
        return
    fi
    local found=0 provider_dir provider f
    for provider_dir in "$MAPS_DIR"/*/; do
        [ -d "$provider_dir" ] || continue
        provider="$(basename "$provider_dir")"
        for f in "$provider_dir"*; do
            [ -f "$f" ] || continue
            found=1
            echo "$provider/$(basename "$f")"
        done
    done
    [ "$found" -eq 1 ] || warn "No maps found."
}

download_map() {
    read -rp "Provider: " PROVIDER || { echo; return; }
    read -rp "Filename: " FNAME || { echo; return; }
    [ -n "$PROVIDER" ] && [ -n "$FNAME" ] || { warn "Provider and filename are required."; return; }
    local RESOLVED_ROOT SRC
    RESOLVED_ROOT="$(realpath -m "$MAPS_DIR")"
    SRC="$(realpath -m "$MAPS_DIR/$PROVIDER/$FNAME")"
    case "$SRC" in
        "$RESOLVED_ROOT"/*) ;;
        *) warn "Invalid provider/filename."; return ;;
    esac
    [ -f "$SRC" ] || { warn "Map not found."; return; }
    local DEST="./${FNAME}"
    if [ -f "$DEST" ]; then
        warn "$DEST already exists in the current directory — remove it first or run this from elsewhere."
        return
    fi
    cp "$SRC" "$DEST"
    ok "Saved to $DEST"
}

banner "Admin Fallback CLI (packages + maps, read-only)"
while true; do
    echo ""
    echo "1) List packages"
    echo "2) Download package"
    echo "3) List maps"
    echo "4) Download map"
    echo "5) Exit"
    read -rp "> " CHOICE || { echo; exit 0; }
    case "$CHOICE" in
        1) list_packages ;;
        2) download_package ;;
        3) list_maps ;;
        4) download_map ;;
        5) exit 0 ;;
        *) warn "Invalid choice." ;;
    esac
done
SCRIPT
chmod +x /home/ndukve/IdeaProjects/TAK/admin_fallback.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n /home/ndukve/IdeaProjects/TAK/admin_fallback.sh && echo "admin_fallback.sh: OK"
```

Expected: prints `OK`.

- [ ] **Step 3: Stage (do NOT commit — user commits manually)**

```bash
git add admin_fallback.sh
```

---

### Task 9: Update documentation (INSTALL.md, DIEGIMAS.md)

**Files:**
- Modify: `INSTALL.md`
- Modify: `DIEGIMAS.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Find every remaining port-8888 reference**

```bash
grep -n "8888" INSTALL.md DIEGIMAS.md
```

- [ ] **Step 2: Update each match**

For each match found in Step 1, replace the port-8888 URL with the equivalent admin-panel path. Specifically:
- The "Step 4 — Generate a User Package" download URL (`http://<SERVER_IP>:8888/Alpha1-iTAK.zip`) becomes a note that the package now downloads from the admin panel's Packages tab, or via the field-account login created alongside it (reference Task 3's behavior).
- The "Map Sources" section's `http://<SERVER_IP>:8888/maps/` becomes a reference to the admin panel's Maps tab (`https://<SERVER_IP>:8889/maps`).
- Any Client Plugins section referencing 8888 becomes a reference to the Plugins tab.

Use the Edit tool for each match — there is no fixed count since this depends on what Step 1's grep returns; read the surrounding paragraph for each match before editing so the replacement reads naturally in context, matching the existing prose style already used in these two files (see the Maintenance section added earlier this session for the established tone).

- [ ] **Step 3: Add the field-account concept to Step 4**

In both `INSTALL.md` and `DIEGIMAS.md`'s "Step 4 — Generate a User Package" section, add one paragraph (in English for `INSTALL.md`, Lithuanian for `DIEGIMAS.md`) noting that generating a package through the web UI also creates a login for that person (username = base callsign, password shown once) so they can log into the admin panel themselves and download their own package(s) from their phone, instead of the operator having to hand over a file directly.

- [ ] **Step 4: Verify no 8888 references remain**

```bash
grep -c "8888" INSTALL.md DIEGIMAS.md
```

Expected: both print `0`.

- [ ] **Step 5: Commit**

```bash
git add INSTALL.md DIEGIMAS.md
git commit -m "docs: update INSTALL.md/DIEGIMAS.md for retired port 8888, field account login"
```

---

### Task 10: End-to-end manual verification

**Files:** none — verification only, no code changes.

**Interfaces:** none.

- [ ] **Step 1: Deploy**

```bash
cd ~/tak-server
git pull
sudo ./update.sh
```

Expected: completes with `Update complete`, self-test passes (per this session's earlier `update.sh` work).

- [ ] **Step 2: Generate a test package via the web UI, capture the field password**

In the admin panel: Users → New User → callsign `FieldTest`, client type `iTAK` → Create. Note the shown-once field account password from the success screen.

- [ ] **Step 3: Log in as the field account**

Log out, log back in with username `FieldTest` and the captured password. Confirm the nav shows only Packages and Maps — no Dashboard, Users, Plugins, Logs, Shell, or Admin Users links.

- [ ] **Step 4: Confirm package scoping**

On the Packages page as `FieldTest`, confirm only `FieldTest-iTAK` is listed. Then, still logged in as `FieldTest`, attempt to fetch another existing package directly:

```bash
curl -k -H "Authorization: Bearer <FieldTest's token from browser devtools>" \
  https://<SERVER_IP>:8889/api/packages/SomeOtherUser-iTAK/download
```

Expected: `404 Not Found` (not the file, and not a 403 that would confirm the file's existence).

- [ ] **Step 5: Confirm generating a second package for the same base name reuses the account**

As superadmin, generate `FieldTest-ATAK`. Expected: response note says an existing field login was reused (no new password shown). Log back in as `FieldTest` — confirm both `FieldTest-iTAK` and `FieldTest-ATAK` now appear in Packages.

- [ ] **Step 6: Confirm route guards**

While still logged in as `FieldTest`, manually navigate the browser to `/users`, `/logs`, `/shell`, and `/admin-users`. Expected: each redirects back to `/packages` (per Task 5, Step 2).

- [ ] **Step 7: Confirm maps still work and are unfiltered for field**

As `FieldTest`, open Maps — confirm all ~40 map sources are listed (proving the Task 2 directory-mismatch fix worked) and that clicking Download on any of them actually downloads the XML file.

- [ ] **Step 8: Confirm port 8888 is gone**

```bash
curl -s -o /dev/null -w "%{http_code}\n" --max-time 3 http://<SERVER_IP>:8888/ || echo "connection refused (expected)"
```

Expected: connection refused/timeout, not an HTTP response.

- [ ] **Step 9: Confirm the break-glass script works with the panel down**

```bash
docker compose --env-file takserver.env stop admin admin_proxy
./get_package.sh FieldTest-iTAK
ls -la FieldTest-iTAK.zip
docker compose --env-file takserver.env start admin admin_proxy
```

Expected: the zip is retrieved successfully even with the admin panel containers stopped, proving it doesn't depend on the panel being up. Clean up the downloaded test file afterward.

- [ ] **Step 10: Clean up test artifacts**

```bash
rm -f FieldTest-iTAK.zip
```

In the admin panel (as superadmin), delete the `FieldTest-iTAK` and `FieldTest-ATAK` packages, then go to Admin Users, toggle "Show field accounts," and delete the `FieldTest` field account.
