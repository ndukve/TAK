# Runtime Branding (Logo, Org Name, Accent Color) — Design

## Purpose

Branding today (`admin/ui/src/brand.ts`) is a build-time TypeScript config selected via a `VITE_BRAND` env var — changing org name, accent color, or adding a logo requires editing code and rebuilding. This replaces that with a superadmin-editable settings page in the admin web UI: upload a logo, set the org name, and pick the accent colors, all without a rebuild. This was explicitly flagged as a deferred follow-up in the original restyle plan ("adding a real second brand with a logo file is a natural follow-up once one actually exists").

## Non-goals

- No multi-brand/per-tenant branding — one deployment has exactly one active brand, same as today.
- No live push to already-open browser tabs — changes apply on next page load/refresh, matching the old rebuild-to-rebrand expectation.
- No logo cropping/resizing UI — uploaded image is used as-is (client-side CSS constrains its display size).
- No branding history/versioning — saving overwrites the single settings row; no undo beyond re-uploading the previous logo/values.

## Architecture

**Data model**: new `BrandSettings` table (`admin/api/models.py`), a settings singleton (always exactly one row, fixed id):

```python
class BrandSettings(Base):
    __tablename__ = "brand_settings"
    id: Mapped[str] = mapped_column(String(16), primary_key=True, default=lambda: "singleton")
    org_name: Mapped[str] = mapped_column(String(64), default="TAK Admin")
    accent_fill: Mapped[str] = mapped_column(String(16), default="#d4d4d8")
    accent_fill_hover: Mapped[str] = mapped_column(String(16), default="#e4e4e7")
    accent_text: Mapped[str] = mapped_column(String(16), default="#18181b")
    accent_ring: Mapped[str] = mapped_column(String(16), default="#a1a1aa")
    logo_filename: Mapped[str | None] = mapped_column(String(128), nullable=True)
```

Created via the existing idempotent-migration pattern in `main.py`'s lifespan (`CREATE TABLE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS`, no Alembic), matching how every other schema change in this app has been handled. On first read with no row present, the API creates one with the defaults above (same values `brand.ts` hardcodes today) — no explicit "first-run setup" step needed.

**Logo storage**: saved to disk at `/opt/tak/data/branding/logo.<ext>` (under the existing `takserver_data` volume, already mounted into `admin` — no new volume needed), same convention as packages/plugins/maps. `logo_filename` stores just the filename (e.g. `logo.png`); a new static route serves it.

## API (`admin/api/branding.py`, new file)

- `GET /api/branding` — **public, unauthenticated**. Returns `{org_name, accent_fill, accent_fill_hover, accent_text, accent_ring, logo_url}` (`logo_url` is `null` if no logo uploaded). Public because the login page needs branding before anyone's authenticated.
- `PUT /api/branding` — **superadmin only**. Body: `{org_name, accent_fill, accent_fill_hover, accent_text, accent_ring}` (all optional, partial update). Validates hex color format and org_name length.
- `POST /api/branding/logo` — **superadmin only**. `UploadFile`, validates it's an image (`.png`/`.jpg`/`.svg`), deletes any existing file in `/opt/tak/data/branding/` first (avoids orphaning a previous logo if the extension changes, e.g. `.png` → `.svg`), saves the new one, updates `logo_filename`.
- `DELETE /api/branding/logo` — **superadmin only**. Removes the logo file and clears `logo_filename`, reverting to text-only branding.
- Logo serving: `GET /api/branding/logo/{filename}` — public (same reasoning as the settings endpoint — the logo needs to render on the login page).

All mutating endpoints call the existing `write_audit()` helper (matches every other admin action in this app).

## Frontend

- `brand.ts`'s `BRANDS` record and `VITE_BRAND` env var are removed entirely.
- `applyBrand()` becomes `async`, fetches `GET /api/branding` at startup (same timing as today, before `RouterProvider` renders), and calls `document.documentElement.style.setProperty(...)` with whatever it gets. On fetch failure (network hiccup, first-boot race), falls back to the same hardcoded defaults currently in `BRANDS.default` — the app never fails to render for branding reasons.
- New route `admin/ui/src/routes/branding.tsx` — superadmin-only nav item (added to `superAdminItems` in `Layout.tsx`, alongside Audit Log). Form: org name text input, four color pickers (fill/hover/text/ring) with live preview swatches, logo upload (drag-drop or file picker) with current-logo preview and a remove button.
- Sidebar org name (`Layout.tsx`) and login page both read from a shared `useBranding()` hook (fetches once, cached) instead of the static `brand.orgName` import.

## Error handling

- Invalid hex color on `PUT /api/branding` → 400 with field-specific message.
- Logo upload: reject non-image content-type and files over 2MB → 400.
- Missing logo file on disk but `logo_filename` still set in DB (manual deletion, volume issue) → `logo_url` omitted from `GET /api/branding` response rather than a broken `<img>` tag (checked with `os.path.isfile` before including the URL).

## Testing

Manual verification per this repo's existing convention (no automated frontend tests yet): `tsc --noEmit` clean, `ruff check` clean on the new `branding.py`, and a manual pass — upload a logo, change colors, refresh the login page (logged out) and confirm both reflect the change, then remove the logo and confirm fallback to text-only.
