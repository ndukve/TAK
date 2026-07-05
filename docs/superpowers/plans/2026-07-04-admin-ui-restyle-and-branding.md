# Admin UI Restyle + Branding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swap the admin panel's accent color from blue to a dark-grey (still high-contrast against the near-black background), add a swappable branding config (org name, accent color, optional logo) driven by a build-time env var, show a "logged in as X (role)" identity footer in the sidebar, group the sidebar nav into regular vs. admin-only sections with a visual divider, and restyle the Dashboard's `ServiceCard` with a bordered/badge/category-label card language borrowed from a reference UI.

**Architecture:** Tailwind v4 CSS-first config — a `@theme` block in `index.css` defines `--color-accent-*` utilities that resolve through `--brand-*` CSS custom properties (with grey fallbacks), so `brand.ts` can override them at runtime via one `document.documentElement.style.setProperty(...)` call without touching any component. The JWT payload gains a `username` claim so the sidebar can show identity without a new endpoint.

**Tech Stack:** React, TypeScript, Tailwind CSS v4, TanStack Router, FastAPI, python-jose.

## Global Constraints

- No automated test framework in this repo — verification is `npm run type-check` (must stay a clean `tsc --noEmit`) for frontend changes and `python3 -c "import ast; ast.parse(...)"` for backend changes.
- Accent color: light-grey fill on dark background for contrast — `#d4d4d8` (Tailwind `zinc-300`) default fill, `#e4e4e7` (`zinc-200`) hover, `#18181b` (`zinc-900`) text-on-fill, `#a1a1aa` (`zinc-400`) for focus rings. These are exact values, not placeholders — use them verbatim.
- The password-strength meter's "Good" color (`Layout.tsx`, `passwordStrength()` function, currently `bg-blue-500`) is a semantic status color (part of a red/yellow/blue/green strength gradient), not a UI accent — it stays blue and must NOT be swapped to the grey accent.
- Branding is implemented as a plain TypeScript config record keyed by brand name (not a folder-per-brand filesystem structure) — there is exactly one brand today and no logo asset exists yet, so building folder-scanning/asset-loading code now would have nothing real to load. Adding a real second brand with a logo file is a natural follow-up once one actually exists, not part of this plan.
- Never commit — stage with `git add <exact files>` and stop. The user commits everything themselves, manually, on their own schedule.
- The spec's "button pairing" point (filled-primary + ghost-secondary, like the reference's LAUNCH/DOCS) is already satisfied for labeled two-button pairs (every Cancel/Submit modal pair already uses `bg-zinc-700` ghost + a filled accent color — Task 2's color swap is the only change those need) — no separate task. It's deliberately NOT applied to the small icon-only Download/Delete pairs in table rows (Packages/Maps/Users) — the reference's pattern was designed for spacious cards, and adding filled backgrounds to dense per-row icon buttons would look heavier, not more polished, in that context.

---

### Task 1: Branding config + accent-color CSS plumbing

**Files:**
- Create: `admin/ui/src/brand.ts`
- Modify: `admin/ui/src/index.css`
- Modify: `admin/ui/src/main.tsx`

**Interfaces:**
- Produces: `applyBrand()` function (exported from `brand.ts`), called once at app startup from `main.tsx`. Produces Tailwind utility classes `bg-accent-fill`, `hover:bg-accent-fill-hover`, `text-accent-text`, `focus:ring-accent-ring`, `border-accent-fill` — later tasks use these exact class names when swapping blue classes.

- [ ] **Step 1: Add the accent-color theme block**

Add this block to the top of `admin/ui/src/index.css`, right after the existing `@import` lines:

```css
@import "tailwindcss";
@import "@xterm/xterm/css/xterm.css";

@theme {
  --color-accent-fill: var(--brand-accent-fill, #d4d4d8);
  --color-accent-fill-hover: var(--brand-accent-fill-hover, #e4e4e7);
  --color-accent-text: var(--brand-accent-text, #18181b);
  --color-accent-ring: var(--brand-accent-ring, #a1a1aa);
}
```

- [ ] **Step 2: Create the brand config**

Create `admin/ui/src/brand.ts`:

```typescript
interface BrandConfig {
  orgName: string
  accentFill: string
  accentFillHover: string
  accentText: string
  accentRing: string
}

const BRANDS: Record<string, BrandConfig> = {
  default: {
    orgName: 'TAK Admin',
    accentFill: '#d4d4d8',
    accentFillHover: '#e4e4e7',
    accentText: '#18181b',
    accentRing: '#a1a1aa',
  },
}

export const brand: BrandConfig = BRANDS[import.meta.env.VITE_BRAND ?? 'default'] ?? BRANDS.default

export function applyBrand() {
  const root = document.documentElement.style
  root.setProperty('--brand-accent-fill', brand.accentFill)
  root.setProperty('--brand-accent-fill-hover', brand.accentFillHover)
  root.setProperty('--brand-accent-text', brand.accentText)
  root.setProperty('--brand-accent-ring', brand.accentRing)
}
```

- [ ] **Step 3: Call it at startup**

Modify `admin/ui/src/main.tsx`:

```typescript
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import { routeTree } from './routeTree.gen'
import { applyBrand } from './brand'
import './index.css'

applyBrand()

const router = createRouter({ routeTree })

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <RouterProvider router={router} />
  </StrictMode>
)
```

- [ ] **Step 4: Verify**

```bash
cd admin/ui && npm run type-check
```

Expected: clean (no errors).

- [ ] **Step 5: Stage (do NOT commit)**

```bash
git add admin/ui/src/brand.ts admin/ui/src/index.css admin/ui/src/main.tsx
```

---

### Task 2: Swap blue accent to grey across all 8 files

**Files:**
- Modify: `admin/ui/src/components/Layout.tsx:107` (NOT line 40 — see Global Constraints)
- Modify: `admin/ui/src/routes/login.tsx:57,67,73`
- Modify: `admin/ui/src/routes/admin-users.tsx:58,63,76,131`
- Modify: `admin/ui/src/routes/users.tsx:70,76,87,100,177,278`
- Modify: `admin/ui/src/routes/packages.tsx:97,133`
- Modify: `admin/ui/src/routes/maps.tsx:116`
- Modify: `admin/ui/src/routes/plugins.tsx:92,138`
- Modify: `admin/ui/src/routes/shell.tsx:105,110`

**Interfaces:**
- Consumes: `bg-accent-fill`, `hover:bg-accent-fill-hover`, `text-accent-text`, `focus:ring-accent-ring`, `border-accent-fill` (Task 1's Tailwind utilities).

- [ ] **Step 1: Replace every filled-button occurrence**

In every file/line listed above (except `Layout.tsx:40`), replace the pattern `bg-blue-600 hover:bg-blue-500` with `bg-accent-fill hover:bg-accent-fill-hover text-accent-text`. Example — `admin/ui/src/routes/login.tsx:73`, before:

```tsx
className="w-full py-2 rounded-md bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium disabled:opacity-50 transition-colors"
```

after:

```tsx
className="w-full py-2 rounded-md bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm font-medium disabled:opacity-50 transition-colors"
```

Apply the same `bg-blue-600 hover:bg-blue-500` → `bg-accent-fill hover:bg-accent-fill-hover text-accent-text` substitution (and drop any co-occurring `text-white` on that same element, replaced by `text-accent-text`) at every line listed in Files above, except `Layout.tsx:40`.

- [ ] **Step 2: Replace every focus-ring occurrence**

Replace `focus:ring-blue-500` with `focus:ring-accent-ring` at: `login.tsx:57,67`, `admin-users.tsx:58,63`, `users.tsx:70,76`, `shell.tsx:105`.

- [ ] **Step 3: Replace the remaining non-button accents**

- `packages.tsx:133`: replace `ring-blue-600` with `ring-accent-fill` in the template literal `` `bg-zinc-950 hover:bg-zinc-900/50 cursor-pointer ${selected?.name === p.name ? 'ring-1 ring-inset ring-blue-600' : ''}` ``.
- `users.tsx:100`: replace `border-blue-500 bg-blue-500/10` with `border-accent-fill bg-accent-fill/10` in the wizard step-indicator template literal.

- [ ] **Step 4: Confirm `Layout.tsx:40` was left untouched**

```bash
grep -n "blue" admin/ui/src/components/Layout.tsx
```

Expected: exactly one match, line 40 (`bg-blue-500` inside `passwordStrength()`), nothing else.

- [ ] **Step 5: Verify no blue accent references remain elsewhere**

```bash
grep -rn "blue-600\|blue-500\|focus:ring-blue" admin/ui/src | grep -v "components/Layout.tsx:40"
```

Expected: no output.

- [ ] **Step 6: Type-check**

```bash
cd admin/ui && npm run type-check
```

Expected: clean.

- [ ] **Step 7: Stage (do NOT commit)**

```bash
git add admin/ui/src/components/Layout.tsx admin/ui/src/routes/login.tsx admin/ui/src/routes/admin-users.tsx admin/ui/src/routes/users.tsx admin/ui/src/routes/packages.tsx admin/ui/src/routes/maps.tsx admin/ui/src/routes/plugins.tsx admin/ui/src/routes/shell.tsx
```

---

### Task 3: Add username to the JWT payload

**Files:**
- Modify: `admin/api/auth.py:49` (login endpoint)
- Modify: `admin/api/auth.py:84` (refresh endpoint)
- Modify: `admin/ui/src/store/auth.ts`
- Modify: `admin/ui/src/routes/login.tsx`
- Modify: `admin/ui/src/lib/api.ts`

**Interfaces:**
- Produces: `useAuth` store gains a `username: string | null` field, read by Task 4's sidebar footer.

- [ ] **Step 1: Add username to both JWT-issuing call sites**

In `admin/api/auth.py`, line 49 (inside `login()`), change:

```python
access_token = create_access_token({"sub": user.id, "role": user.role})
```

to:

```python
access_token = create_access_token({"sub": user.id, "role": user.role, "username": user.username})
```

Make the identical change at line 84 (inside `refresh()`) — same before/after text.

- [ ] **Step 2: Verify backend syntax**

```bash
python3 -c "import ast; ast.parse(open('admin/api/auth.py').read())"
```

Expected: no output (success).

- [ ] **Step 3: Add username to the auth store**

Modify `admin/ui/src/store/auth.ts`:

```typescript
import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface AuthState {
  token: string | null
  role: string | null
  username: string | null
  passwordExpired: boolean
  setToken: (token: string, role: string, username: string) => void
  setPasswordExpired: (v: boolean) => void
  clear: () => void
}

export const useAuth = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      role: null,
      username: null,
      passwordExpired: false,
      setToken: (token, role, username) => set({ token, role, username }),
      setPasswordExpired: (v) => set({ passwordExpired: v }),
      clear: () => set({ token: null, role: null, username: null, passwordExpired: false }),
    }),
    { name: 'tak-admin-auth' }
  )
)
```

- [ ] **Step 4: Decode and pass username at login**

In `admin/ui/src/routes/login.tsx`, find the line that calls `setToken(access_token, payload.role)` and change it to `setToken(access_token, payload.role, payload.username)`. The `payload` variable there is already `JSON.parse(atob(access_token.split('.')[1]))` — no other change needed, `payload.username` is simply now present because of Step 1.

- [ ] **Step 5: Decode and pass username on silent refresh**

In `admin/ui/src/lib/api.ts`, inside `refreshToken()`, find:

```typescript
useAuth.getState().setToken(data.access_token, payload.role)
```

and change it to:

```typescript
useAuth.getState().setToken(data.access_token, payload.role, payload.username)
```

- [ ] **Step 6: Type-check**

```bash
cd admin/ui && npm run type-check
```

Expected: clean.

- [ ] **Step 7: Stage (do NOT commit)**

```bash
git add admin/api/auth.py admin/ui/src/store/auth.ts admin/ui/src/routes/login.tsx admin/ui/src/lib/api.ts
```

---

### Task 4: Sidebar section grouping + user identity footer

**Files:**
- Modify: `admin/ui/src/components/Layout.tsx`

**Interfaces:**
- Consumes: `useAuth`'s `username` field (Task 3), `brand.orgName` (Task 1's `brand.ts`), `bg-accent-fill`/`text-accent-text` utilities (Task 1).

- [ ] **Step 1: Import brand and read username from the store**

At the top of `Layout.tsx`, add:

```typescript
import { brand } from '@/brand'
```

Change the line `const { role, clear, passwordExpired, setPasswordExpired } = useAuth()` to:

```typescript
const { role, username, clear, passwordExpired, setPasswordExpired } = useAuth()
```

- [ ] **Step 2: Replace the hardcoded org name**

Find:

```tsx
<span className="font-bold text-lg tracking-tight">TAK Admin</span>
```

Replace with:

```tsx
<span className="font-bold text-lg tracking-tight">{brand.orgName}</span>
```

- [ ] **Step 3: Split the nav into grouped sections**

Find the current nav-items computation:

```tsx
const items = role === 'field' ? fieldItems
  : role === 'superadmin' ? [...navItems, ...superAdminItems]
  : navItems
```

Replace with two separate variables (drop the combined `items` variable entirely):

```tsx
const items = role === 'field' ? fieldItems : navItems
const adminItems = role === 'superadmin' ? superAdminItems : []
```

Find the nav rendering block:

```tsx
<nav className="flex-1 p-2 space-y-1">
  {items.map(({ to, label, icon: Icon }) => (
    <Link
      key={to}
      to={to}
      onClick={() => setSidebarOpen(false)}
      className={cn(
        'flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors',
        current === to
          ? 'bg-zinc-800 text-white'
          : 'text-zinc-400 hover:text-white hover:bg-zinc-800/50'
      )}
    >
      <Icon size={16} />
      {label}
    </Link>
  ))}
</nav>
```

Replace with (extracting the per-item render into a local helper to avoid duplicating the `Link` markup for the two groups):

```tsx
<nav className="flex-1 p-2 space-y-1">
  {items.map(({ to, label, icon: Icon }) => (
    <Link
      key={to}
      to={to}
      onClick={() => setSidebarOpen(false)}
      className={cn(
        'flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors',
        current === to
          ? 'bg-zinc-800 text-white'
          : 'text-zinc-400 hover:text-white hover:bg-zinc-800/50'
      )}
    >
      <Icon size={16} />
      {label}
    </Link>
  ))}
  {adminItems.length > 0 && (
    <>
      <div className="pt-3 pb-1 px-3 text-[10px] font-semibold tracking-wider text-zinc-600 uppercase">Admin</div>
      {adminItems.map(({ to, label, icon: Icon }) => (
        <Link
          key={to}
          to={to}
          onClick={() => setSidebarOpen(false)}
          className={cn(
            'flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors',
            current === to
              ? 'bg-zinc-800 text-white'
              : 'text-zinc-400 hover:text-white hover:bg-zinc-800/50'
          )}
        >
          <Icon size={16} />
          {label}
        </Link>
      ))}
    </>
  )}
</nav>
```

- [ ] **Step 4: Add the identity footer above the Change Password/Sign out buttons**

Find:

```tsx
<div className="p-2 border-t border-zinc-800 space-y-1">
  <button
    onClick={() => setShowChangePw(true)}
```

Replace with:

```tsx
<div className="px-3 py-3 border-t border-zinc-800 flex items-center gap-2">
  <div className="w-7 h-7 rounded-full bg-accent-fill text-accent-text flex items-center justify-center text-xs font-semibold shrink-0">
    {(username ?? '?').slice(0, 2).toUpperCase()}
  </div>
  <div className="min-w-0">
    <p className="text-sm text-zinc-200 truncate">{username}</p>
    <p className="text-xs text-zinc-500">{role}</p>
  </div>
</div>
<div className="p-2 border-t border-zinc-800 space-y-1">
  <button
    onClick={() => setShowChangePw(true)}
```

(This wraps the identity block in its own bordered section directly above the existing button section, which keeps its own `border-t` — leaving two stacked divider lines is intentional, matching the reference screenshot's distinct visual separation between identity and actions.)

- [ ] **Step 5: Type-check**

```bash
cd admin/ui && npm run type-check
```

Expected: clean.

- [ ] **Step 6: Stage (do NOT commit)**

```bash
git add admin/ui/src/components/Layout.tsx
```

---

### Task 5: Restyle the Dashboard's ServiceCard

**Files:**
- Modify: `admin/ui/src/routes/index.tsx`

**Interfaces:**
- Consumes: `bg-accent-fill`/`text-accent-text` (Task 1). No new props on `ServiceCard` — same `ServiceState` shape as today.

- [ ] **Step 1: Replace the ServiceCard component**

Find the current `ServiceCard` function:

```tsx
function ServiceCard({ service }: { service: ServiceState }) {
  const running = service.status === 'running'
  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs font-mono text-zinc-400">{service.name}</span>
        {running
          ? <CheckCircle size={14} className="text-green-500" />
          : <XCircle size={14} className="text-red-500" />
        }
      </div>
      <span className={cn('text-sm font-medium', running ? 'text-green-400' : 'text-red-400')}>
        {service.status}
      </span>
    </div>
  )
}
```

Replace with:

```tsx
function ServiceCard({ service }: { service: ServiceState }) {
  const running = service.status === 'running'
  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <div className="flex items-start justify-between mb-3">
        <span className="text-[10px] font-semibold tracking-wider text-zinc-500 uppercase">Service</span>
        <div className={cn(
          'w-7 h-7 rounded-md border flex items-center justify-center shrink-0',
          running ? 'border-green-800 bg-green-500/10' : 'border-red-800 bg-red-500/10'
        )}>
          {running
            ? <CheckCircle size={14} className="text-green-500" />
            : <XCircle size={14} className="text-red-500" />
          }
        </div>
      </div>
      <p className="text-sm font-medium text-zinc-200 font-mono mb-2">{service.name}</p>
      <div className="border-t border-zinc-800 pt-2">
        <span className={cn('text-xs font-medium', running ? 'text-green-400' : 'text-red-400')}>
          {service.status}
        </span>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Type-check**

```bash
cd admin/ui && npm run type-check
```

Expected: clean.

- [ ] **Step 3: Stage (do NOT commit)**

```bash
git add admin/ui/src/routes/index.tsx
```

---
