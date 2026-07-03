# Admin UI Restyle + Branding System — Design

## Purpose

Keep this admin panel's existing page structure and information architecture (it works, and a full rebuild isn't warranted), but adopt several concrete visual patterns from Rasenmaeher's Deploy App UI (a Finnish Transport Agency mTLS/service-launcher platform, screenshot reference provided 2026-07-04) that make it read as more "production dashboard" rather than a bare CRUD utility. Alongside this, add a swappable branding/theming config, matching Rasenmaeher's `VITE_ASSET_SET` pattern, so logo/org-name/accent-color aren't hardcoded across ~10 files.

## Non-goals

- No framework change, no page-structure rebuild, no new information architecture — same routes, same data, same nav destinations.
- No mimicking Rasenmaeher's "service launcher" home-page concept literally (we don't have multiple external services to launch into) — only the transferable visual patterns (cards, sidebar grouping, identity footer) get adopted, not the page's actual purpose.

## Accent color

Confirmed: replace blue with a dark-grey accent that still reads clearly against the near-black `zinc-950` page background — not a low-contrast near-black-on-black grey. Concretely: primary filled buttons/active-nav-highlight move from `bg-blue-600 hover:bg-blue-500` to a light-grey-on-dark treatment, e.g. `bg-zinc-300 hover:bg-zinc-200 text-zinc-900` (light grey fill, dark text — reads as a distinct "steel/graphite" accent against the existing `zinc-800`/`zinc-900` card and border tones, rather than blending in). Focus rings (`focus:ring-blue-500`) move to `focus:ring-zinc-400`. This becomes the default value baked into `brand.ts` (see below), not a one-off — a future brand variant can still override it.

## What's being adopted, concretely

From the reference screenshot:

1. **Sidebar section grouping.** Today `Layout.tsx` concatenates `navItems` and `superAdminItems` into one flat list for superadmins, with no visual distinction. Add a small-caps section label (e.g. "ADMIN") above the superadmin-only items, with a divider, mirroring the reference's "ADMINISTRATORS" grouping. `fieldItems`/`navItems` stay as-is (no superadmin items to group for those roles).
2. **User identity footer.** The reference pins an avatar + username + role at the bottom of the sidebar. We show none of this today — only "Change Password"/"Sign out" buttons. Add a small identity block (initials-in-circle avatar, username, role badge) above those buttons, using data already in the JWT payload (`role`) plus the username the frontend already has from login.
3. **Card restyle.** The reference's cards (bordered, rounded, icon-badge top-right, small all-caps category label top-left, divider before the action row) get adopted for the Dashboard's `ServiceCard` (existing) and the `SystemStatCard`/`CertList` cards (spec'd in `2026-07-03-dashboard-hardware-stats-design.md`, not yet built — this restyle's card language supersedes that spec's plainer sketch, so implement that spec's cards using this visual language when it's built).
4. **Button pairing.** Where two related actions sit side by side (e.g. Download + Delete on Packages/Maps rows), standardize on filled-primary + ghost-secondary, matching the reference's "LAUNCH" (filled) + "DOCS" (ghost) pairing. This is a visual-consistency pass over existing buttons, not new functionality.

## Branding/theming system

- New `admin/ui/src/brand.ts` exporting a small config object: org display name (replaces hardcoded "TAK Admin" in the sidebar header), logo path (optional — falls back to text-only if absent), accent color (CSS custom property, defaults to the dark-grey accent above).
- Selected via one build-time env var, e.g. `VITE_BRAND=default`, resolving to `admin/ui/brand/<name>/` — a folder holding the config + optional logo image, mirroring Rasenmaeher's `assetSetStore/<name>/` pattern. Adding a new brand variant is "add a folder, set the env var," no code changes.
- The accent color becomes a CSS variable (`--accent`) consumed by a small set of shared Tailwind utility classes, replacing the ~22 hardcoded `blue-600`/`blue-500` occurrences across the codebase. This is the mechanical piece that makes a future accent-color change a config edit instead of a find-and-replace.

## Testing

No automated test framework in this repo. Verification: `npm run type-check` (clean `tsc --noEmit`), and a manual visual check of the Dashboard, sidebar, and one CRUD page (e.g. Packages) after the restyle — confirming the sidebar grouping/footer render correctly for each role (field/admin/superadmin) and the default brand config produces an identical look to today (since nothing about accent color is changing yet, this should be a no-visible-diff sanity check for the branding plumbing itself).
