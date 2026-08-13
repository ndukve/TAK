# TAK Admin Panel — Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a React admin UI for the TAK server, matching the look and feel of `deploy/uiv2`, served as static files from the FastAPI backend container.

**Architecture:** React 18 + Vite + TypeScript + Tailwind CSS + shadcn/ui + TanStack Router. Built to `admin/ui/dist/`, which FastAPI serves at `/`. During development, Vite dev server proxies API calls to `localhost:8889`.

**Tech Stack:** React 18, Vite, TypeScript, Tailwind CSS v4, shadcn/ui, TanStack Router, TanStack Query (react-query), Zustand, xterm.js, react-qr-code, lucide-react.

**Prerequisite:** Backend plan (`2026-06-25-admin-panel-backend.md`) must be complete and running on `:8889`.

## Global Constraints

- Match deploy/uiv2 visual style: same shadcn/ui components, same Tailwind approach
- All API calls use JWT from Zustand auth store; auto-refresh via interceptor
- Route guard: redirect to `/login` if no valid token
- Role guard: `superadmin`-only routes redirect to `/` for lesser roles
- xterm.js terminal used for both logs (read-only) and shell (interactive)
- No i18n — English only (unlike deploy/uiv2)
- Build output: `admin/ui/dist/` — copied into Docker image at build time

---

### Task 1: UI scaffold

**Files:**
- Create: `admin/ui/package.json`
- Create: `admin/ui/vite.config.ts`
- Create: `admin/ui/tsconfig.json`
- Create: `admin/ui/tsconfig.app.json`
- Create: `admin/ui/tsconfig.node.json`
- Create: `admin/ui/index.html`
- Create: `admin/ui/src/main.tsx`
- Create: `admin/ui/src/index.css`
- Create: `admin/ui/src/lib/utils.ts`
- Modify: `admin/Dockerfile` (add UI build stage)

**Interfaces:**
- Produces: `pnpm dev` opens Vite dev server at `localhost:5173`

- [ ] **Step 1: Write admin/ui/package.json**

```json
{
  "name": "tak-admin-ui",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@radix-ui/react-avatar": "^1.1.10",
    "@radix-ui/react-dialog": "^1.1.15",
    "@radix-ui/react-dropdown-menu": "^2.1.16",
    "@radix-ui/react-label": "^2.1.7",
    "@radix-ui/react-select": "^2.2.6",
    "@radix-ui/react-separator": "^1.1.7",
    "@radix-ui/react-slot": "^1.2.3",
    "@radix-ui/react-tabs": "^1.1.13",
    "@radix-ui/react-tooltip": "^1.2.8",
    "@tanstack/react-router": "^1.133.22",
    "@xterm/xterm": "^5.5.0",
    "@xterm/addon-fit": "^0.10.0",
    "@xterm/addon-web-links": "^0.11.0",
    "class-variance-authority": "^0.7.1",
    "clsx": "^2.1.1",
    "lucide-react": "^0.552.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-qr-code": "^2.0.18",
    "sonner": "^2.0.7",
    "tailwind-merge": "^3.3.1",
    "tailwindcss": "^4.1.16",
    "zustand": "^5.0.8"
  },
  "devDependencies": {
    "@tailwindcss/vite": "^4.1.16",
    "@tanstack/router-plugin": "^1.133.22",
    "@types/node": "^24.0.0",
    "@types/react": "18.2.79",
    "@types/react-dom": "18.2.25",
    "@vitejs/plugin-react": "4.2.1",
    "typescript": "5.4.5",
    "vite": "5.2.10"
  }
}
```

- [ ] **Step 2: Write admin/ui/vite.config.ts**

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { TanStackRouterVite } from '@tanstack/router-plugin/vite'
import path from 'path'

export default defineConfig({
  plugins: [
    TanStackRouterVite({ routesDirectory: './src/routes', generatedRouteTree: './src/routeTree.gen.ts' }),
    react(),
    tailwindcss(),
  ],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    proxy: {
      '/api': 'http://localhost:8889',
      '/auth': 'http://localhost:8889',
    },
  },
  build: {
    outDir: 'dist',
  },
})
```

- [ ] **Step 3: Write tsconfig files**

`admin/ui/tsconfig.json`:
```json
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ]
}
```

`admin/ui/tsconfig.app.json`:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["src"]
}
```

`admin/ui/tsconfig.node.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "skipLibCheck": true
  },
  "include": ["vite.config.ts"]
}
```

- [ ] **Step 4: Write admin/ui/index.html**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>TAK Admin</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 5: Write admin/ui/src/main.tsx**

```typescript
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import { routeTree } from './routeTree.gen'
import './index.css'

const router = createRouter({ routeTree })

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <RouterProvider router={router} />
  </StrictMode>
)
```

- [ ] **Step 6: Write admin/ui/src/index.css**

```css
@import "tailwindcss";
@import "@xterm/xterm/css/xterm.css";
```

- [ ] **Step 7: Write admin/ui/src/lib/utils.ts**

```typescript
import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
```

- [ ] **Step 8: Install dependencies and verify dev server starts**

```bash
cd admin/ui
pnpm install
pnpm dev
```

Expected: Vite starts on `localhost:5173` (will show blank page until routes are added).

- [ ] **Step 9: Update admin/Dockerfile to build UI**

```dockerfile
FROM node:20-slim AS ui-builder
WORKDIR /ui
RUN npm install -g pnpm
COPY ui/package.json ui/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY ui/ .
RUN pnpm build

FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api/ ./api/
COPY --from=ui-builder /ui/dist ./ui/dist
EXPOSE 8889
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8889"]
```

- [ ] **Step 10: Commit**

```bash
git add admin/ui/ admin/Dockerfile
git commit -m "feat: scaffold React+Vite+Tailwind admin UI"
```

---

### Task 2: Auth store + API client + root route

**Files:**
- Create: `admin/ui/src/store/auth.ts`
- Create: `admin/ui/src/lib/api.ts`
- Create: `admin/ui/src/routes/__root.tsx`
- Create: `admin/ui/src/routes/login.tsx`

**Interfaces:**
- Produces:
  - `useAuth()` hook with `{ token, role, login, logout }`
  - `api` fetch wrapper with auto-refresh on 401
  - `/__root` route with redirect logic
  - `/login` route with login form

- [ ] **Step 1: Write admin/ui/src/store/auth.ts**

```typescript
import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface AuthState {
  token: string | null
  role: string | null
  setToken: (token: string, role: string) => void
  clear: () => void
}

export const useAuth = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      role: null,
      setToken: (token, role) => set({ token, role }),
      clear: () => set({ token: null, role: null }),
    }),
    { name: 'tak-admin-auth' }
  )
)
```

- [ ] **Step 2: Write admin/ui/src/lib/api.ts**

```typescript
import { useAuth } from '@/store/auth'

const BASE = ''  // same origin in prod; Vite proxy in dev

async function refreshToken(): Promise<string | null> {
  const res = await fetch(`${BASE}/auth/refresh`, { method: 'POST', credentials: 'include' })
  if (!res.ok) return null
  const data = await res.json()
  const payload = JSON.parse(atob(data.access_token.split('.')[1]))
  useAuth.getState().setToken(data.access_token, payload.role)
  return data.access_token
}

export async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const { token, clear } = useAuth.getState()
  const headers = new Headers(init.headers)
  if (token) headers.set('Authorization', `Bearer ${token}`)

  let res = await fetch(`${BASE}${path}`, { ...init, headers, credentials: 'include' })

  if (res.status === 401) {
    const newToken = await refreshToken()
    if (!newToken) {
      clear()
      window.location.href = '/login'
      return res
    }
    headers.set('Authorization', `Bearer ${newToken}`)
    res = await fetch(`${BASE}${path}`, { ...init, headers, credentials: 'include' })
  }

  return res
}

export async function apiJson<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await apiFetch(path, init)
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }))
    throw new Error(err.detail ?? res.statusText)
  }
  return res.json()
}
```

- [ ] **Step 3: Write admin/ui/src/routes/__root.tsx**

```typescript
import { createRootRoute, Outlet, redirect } from '@tanstack/react-router'
import { useAuth } from '@/store/auth'
import { Toaster } from 'sonner'

export const Route = createRootRoute({
  component: () => (
    <>
      <Outlet />
      <Toaster richColors position="top-right" />
    </>
  ),
})
```

- [ ] **Step 4: Write admin/ui/src/routes/login.tsx**

```typescript
import { createFileRoute, useNavigate } from '@tanstack/react-router'
import { useState } from 'react'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'

export const Route = createFileRoute('/login')({
  component: LoginPage,
})

function LoginPage() {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const { setToken } = useAuth()
  const navigate = useNavigate()

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const res = await fetch('/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ username, password }),
      })
      if (!res.ok) {
        const err = await res.json()
        throw new Error(err.detail ?? 'Login failed')
      }
      const { access_token } = await res.json()
      const payload = JSON.parse(atob(access_token.split('.')[1]))
      setToken(access_token, payload.role)
      navigate({ to: '/' })
    } catch (err: any) {
      toast.error(err.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-zinc-950">
      <div className="w-full max-w-sm space-y-6 p-8 rounded-xl border border-zinc-800 bg-zinc-900">
        <div>
          <h1 className="text-2xl font-bold text-white">TAK Admin</h1>
          <p className="text-sm text-zinc-400 mt-1">Sign in to manage your TAK server</p>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1">
            <label className="text-sm text-zinc-300">Username</label>
            <input
              type="text"
              value={username}
              onChange={e => setUsername(e.target.value)}
              required
              className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <div className="space-y-1">
            <label className="text-sm text-zinc-300">Password</label>
            <input
              type="password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              required
              className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <button
            type="submit"
            disabled={loading}
            className="w-full py-2 rounded-md bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium disabled:opacity-50 transition-colors"
          >
            {loading ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
```

- [ ] **Step 5: Verify login page renders**

```bash
cd admin/ui && pnpm dev
# Open http://localhost:5173/login
```

Expected: dark login form renders, submitting with correct credentials redirects to `/`.

- [ ] **Step 6: Commit**

```bash
git add admin/ui/src/store/ admin/ui/src/lib/ admin/ui/src/routes/__root.tsx admin/ui/src/routes/login.tsx
git commit -m "feat: add auth store, API client, login page"
```

---

### Task 3: Layout + protected routes + dashboard

**Files:**
- Create: `admin/ui/src/components/Layout.tsx`
- Create: `admin/ui/src/routes/index.tsx`

**Interfaces:**
- Produces:
  - `<Layout>` sidebar with nav links, role-aware (shell link hidden for non-superadmin)
  - `/` dashboard with service health cards, auto-refreshing every 5s

- [ ] **Step 1: Write admin/ui/src/components/Layout.tsx**

```typescript
import { Link, useNavigate, useRouterState } from '@tanstack/react-router'
import { useAuth } from '@/store/auth'
import { cn } from '@/lib/utils'
import { apiFetch } from '@/lib/api'
import {
  LayoutDashboard, Users, Package, Puzzle, Map,
  ScrollText, Terminal, ShieldUser, LogOut
} from 'lucide-react'

const navItems = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/users', label: 'Users', icon: Users },
  { to: '/packages', label: 'Packages', icon: Package },
  { to: '/plugins', label: 'Plugins', icon: Puzzle },
  { to: '/maps', label: 'Maps', icon: Map },
  { to: '/logs', label: 'Logs', icon: ScrollText },
]

const superAdminItems = [
  { to: '/shell', label: 'Shell', icon: Terminal },
  { to: '/admin-users', label: 'Admin Users', icon: ShieldUser },
]

export function Layout({ children }: { children: React.ReactNode }) {
  const { role, clear } = useAuth()
  const navigate = useNavigate()
  const routerState = useRouterState()
  const current = routerState.location.pathname

  async function handleLogout() {
    await apiFetch('/auth/logout', { method: 'POST' })
    clear()
    navigate({ to: '/login' })
  }

  const items = role === 'superadmin' ? [...navItems, ...superAdminItems] : navItems

  return (
    <div className="flex h-screen bg-zinc-950 text-zinc-100">
      <aside className="w-56 flex-shrink-0 border-r border-zinc-800 flex flex-col">
        <div className="p-4 border-b border-zinc-800">
          <span className="font-bold text-lg tracking-tight">TAK Admin</span>
        </div>
        <nav className="flex-1 p-2 space-y-1">
          {items.map(({ to, label, icon: Icon }) => (
            <Link
              key={to}
              to={to}
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
        <div className="p-2 border-t border-zinc-800">
          <button
            onClick={handleLogout}
            className="flex items-center gap-3 w-full px-3 py-2 rounded-md text-sm text-zinc-400 hover:text-white hover:bg-zinc-800/50 transition-colors"
          >
            <LogOut size={16} />
            Sign out
          </button>
        </div>
      </aside>
      <main className="flex-1 overflow-auto">{children}</main>
    </div>
  )
}
```

- [ ] **Step 2: Write admin/ui/src/routes/index.tsx**

```typescript
import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { CheckCircle, XCircle, Loader } from 'lucide-react'
import { cn } from '@/lib/utils'

export const Route = createFileRoute('/')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: DashboardPage,
})

interface ServiceState {
  name: string
  status: string
  health: string
}

function DashboardPage() {
  const [services, setServices] = useState<ServiceState[]>([])

  async function load() {
    try {
      const data = await apiJson<{ services: ServiceState[] }>('/api/health')
      setServices(data.services)
    } catch {}
  }

  useEffect(() => {
    load()
    const id = setInterval(load, 5000)
    return () => clearInterval(id)
  }, [])

  return (
    <Layout>
      <div className="p-6">
        <h1 className="text-xl font-semibold mb-6">Dashboard</h1>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {services.map(s => (
            <ServiceCard key={s.name} service={s} />
          ))}
        </div>
      </div>
    </Layout>
  )
}

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

- [ ] **Step 3: Verify dashboard**

```bash
pnpm dev
# Log in at /login, should redirect to / and show service health cards
```

Expected: dark sidebar with nav, main area shows service cards with green/red status.

- [ ] **Step 4: Commit**

```bash
git add admin/ui/src/components/Layout.tsx admin/ui/src/routes/index.tsx
git commit -m "feat: add sidebar layout and dashboard with live health cards"
```

---

### Task 4: Users tab

**Files:**
- Create: `admin/ui/src/routes/users.tsx`
- Create: `admin/ui/src/routes/users.new.tsx`

**Interfaces:**
- Produces: `/users` list with enable/disable/delete actions, `/users/new` cert wizard

- [ ] **Step 1: Write admin/ui/src/routes/users.tsx**

```typescript
import { createFileRoute, redirect, Link } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { UserPlus, Trash2, CheckCircle, XCircle } from 'lucide-react'

export const Route = createFileRoute('/users')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: UsersPage,
})

function UsersPage() {
  const [users, setUsers] = useState<string[]>([])

  async function load() {
    try {
      const data = await apiJson<{ users: string[] }>('/api/users')
      setUsers(data.users)
    } catch (e: any) {
      toast.error(e.message)
    }
  }

  useEffect(() => { load() }, [])

  async function enableUser(username: string) {
    try {
      await apiJson('/api/users/enable', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username }),
      })
      toast.success(`${username} enabled`)
    } catch (e: any) { toast.error(e.message) }
  }

  async function disableUser(username: string) {
    try {
      await apiJson('/api/users/disable', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username }),
      })
      toast.success(`${username} disabled`)
    } catch (e: any) { toast.error(e.message) }
  }

  async function deleteUser(username: string) {
    if (!confirm(`Delete ${username}? This cannot be undone.`)) return
    try {
      await apiFetch(`/api/users/${username}`, { method: 'DELETE' })
      toast.success(`${username} deleted`)
      load()
    } catch (e: any) { toast.error(e.message) }
  }

  return (
    <Layout>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-xl font-semibold">TAK Users</h1>
          <Link to="/users/new" className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm rounded-md transition-colors">
            <UserPlus size={14} /> New User
          </Link>
        </div>
        <div className="rounded-lg border border-zinc-800 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">Callsign</th>
                <th className="px-4 py-3 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {users.length === 0 && (
                <tr><td colSpan={2} className="px-4 py-8 text-center text-zinc-500">No users yet — create one</td></tr>
              )}
              {users.map(u => (
                <tr key={u} className="bg-zinc-950 hover:bg-zinc-900/50">
                  <td className="px-4 py-3 font-mono">{u}</td>
                  <td className="px-4 py-3 flex justify-end gap-2">
                    <button onClick={() => enableUser(u)} title="Enable" className="p-1.5 rounded hover:bg-zinc-800 text-green-400"><CheckCircle size={14} /></button>
                    <button onClick={() => disableUser(u)} title="Disable" className="p-1.5 rounded hover:bg-zinc-800 text-yellow-400"><XCircle size={14} /></button>
                    <button onClick={() => deleteUser(u)} title="Delete" className="p-1.5 rounded hover:bg-zinc-800 text-red-400"><Trash2 size={14} /></button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  )
}
```

- [ ] **Step 2: Write admin/ui/src/routes/users.new.tsx**

```typescript
import { createFileRoute, redirect, useNavigate } from '@tanstack/react-router'
import { useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { CheckCircle } from 'lucide-react'

export const Route = createFileRoute('/users/new')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: NewUserPage,
})

type Step = 'form' | 'gen-cert' | 'make-package' | 'enable' | 'done'

function NewUserPage() {
  const [username, setUsername] = useState('')
  const [step, setStep] = useState<Step>('form')
  const [downloadUrl, setDownloadUrl] = useState('')
  const navigate = useNavigate()

  async function runStep(nextStep: Step, endpoint: string, body: object) {
    setStep(nextStep)
    try {
      const data = await apiJson<any>(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })
      if (data.download_url) setDownloadUrl(data.download_url)
    } catch (e: any) {
      toast.error(e.message)
      setStep('form')
    }
  }

  async function handleCreate() {
    if (!username.trim()) return
    await runStep('gen-cert', '/api/users/gen-cert', { username })
    await runStep('make-package', '/api/users/make-package', { username })
    await runStep('enable', '/api/users/enable', { username })
    setStep('done')
  }

  const steps: { id: Step; label: string }[] = [
    { id: 'gen-cert', label: 'Generate device certificate' },
    { id: 'make-package', label: 'Build data package' },
    { id: 'enable', label: 'Authorize on server' },
  ]

  const stepOrder: Step[] = ['form', 'gen-cert', 'make-package', 'enable', 'done']

  return (
    <Layout>
      <div className="p-6 max-w-lg">
        <h1 className="text-xl font-semibold mb-6">New User</h1>

        {step === 'form' && (
          <div className="space-y-4">
            <div className="space-y-1">
              <label className="text-sm text-zinc-300">Callsign</label>
              <input
                type="text"
                value={username}
                onChange={e => setUsername(e.target.value.replace(/[^a-zA-Z0-9_-]/g, ''))}
                placeholder="e.g. alpha-1"
                className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <p className="text-xs text-zinc-500">Letters, numbers, hyphens, underscores only.</p>
            </div>
            <button
              onClick={handleCreate}
              disabled={!username.trim()}
              className="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm rounded-md disabled:opacity-50 transition-colors"
            >
              Create
            </button>
          </div>
        )}

        {step !== 'form' && step !== 'done' && (
          <div className="space-y-3">
            {steps.map(s => {
              const idx = stepOrder.indexOf(s.id)
              const currentIdx = stepOrder.indexOf(step)
              const done = idx < currentIdx
              const active = s.id === step
              return (
                <div key={s.id} className={`flex items-center gap-3 p-3 rounded-lg border ${active ? 'border-blue-500 bg-blue-500/10' : done ? 'border-zinc-700 bg-zinc-900' : 'border-zinc-800 opacity-40'}`}>
                  {done ? <CheckCircle size={16} className="text-green-400 shrink-0" /> : <div className={`w-4 h-4 rounded-full border-2 shrink-0 ${active ? 'border-blue-400 animate-pulse' : 'border-zinc-600'}`} />}
                  <span className="text-sm">{s.label}</span>
                </div>
              )
            })}
          </div>
        )}

        {step === 'done' && (
          <div className="space-y-4">
            <div className="flex items-center gap-2 text-green-400">
              <CheckCircle size={18} />
              <span className="font-medium">{username} is ready</span>
            </div>
            <button
              onClick={() => navigate({ to: '/packages' })}
              className="px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-white text-sm rounded-md transition-colors"
            >
              View packages →
            </button>
          </div>
        )}
      </div>
    </Layout>
  )
}
```

- [ ] **Step 3: Test**

```bash
# Navigate to /users/new, enter a callsign, click Create
# Should show step progress, then "ready" state
# Navigate to /users, should see the new callsign listed
```

- [ ] **Step 4: Commit**

```bash
git add admin/ui/src/routes/users.tsx admin/ui/src/routes/users.new.tsx
git commit -m "feat: add users list and cert creation wizard"
```

---

### Task 5: Packages tab with QR codes

**Files:**
- Create: `admin/ui/src/routes/packages.tsx`

- [ ] **Step 1: Write admin/ui/src/routes/packages.tsx**

```typescript
import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import QRCode from 'react-qr-code'
import { Download } from 'lucide-react'

export const Route = createFileRoute('/packages')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: PackagesPage,
})

interface Package {
  name: string
  filename: string
  size: string
}

const SERVER_ADDR = window.location.hostname

function PackagesPage() {
  const [packages, setPackages] = useState<Package[]>([])
  const [selected, setSelected] = useState<Package | null>(null)

  useEffect(() => {
    apiJson<{ packages: Package[] }>('/api/packages')
      .then(d => setPackages(d.packages))
      .catch(e => toast.error(e.message))
  }, [])

  return (
    <Layout>
      <div className="p-6">
        <h1 className="text-xl font-semibold mb-6">Data Packages</h1>
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <div className="lg:col-span-2 rounded-lg border border-zinc-800 overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-zinc-900 text-zinc-400">
                <tr>
                  <th className="px-4 py-3 text-left font-medium">Callsign</th>
                  <th className="px-4 py-3 text-left font-medium">Size</th>
                  <th className="px-4 py-3 text-right font-medium">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-800">
                {packages.length === 0 && (
                  <tr><td colSpan={3} className="px-4 py-8 text-center text-zinc-500">No packages yet</td></tr>
                )}
                {packages.map(p => (
                  <tr
                    key={p.name}
                    onClick={() => setSelected(p)}
                    className="bg-zinc-950 hover:bg-zinc-900/50 cursor-pointer"
                  >
                    <td className="px-4 py-3 font-mono">{p.name}</td>
                    <td className="px-4 py-3 text-zinc-400">{p.size}</td>
                    <td className="px-4 py-3 flex justify-end">
                      <a
                        href={`http://${SERVER_ADDR}:8888/${p.filename}`}
                        onClick={e => e.stopPropagation()}
                        className="p-1.5 rounded hover:bg-zinc-800 text-blue-400"
                        title="Download"
                      >
                        <Download size={14} />
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {selected && (
            <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4 flex flex-col items-center gap-4">
              <p className="text-sm font-medium text-zinc-300">{selected.name}</p>
              <div className="bg-white p-3 rounded-lg">
                <QRCode
                  value={`http://${SERVER_ADDR}:8888/${selected.filename}`}
                  size={160}
                />
              </div>
              <p className="text-xs text-zinc-500 text-center break-all">
                {`http://${SERVER_ADDR}:8888/${selected.filename}`}
              </p>
            </div>
          )}
        </div>
      </div>
    </Layout>
  )
}
```

- [ ] **Step 2: Test**

Navigate to `/packages` — should list packages with download icons. Clicking a row shows QR code in the right panel.

- [ ] **Step 3: Commit**

```bash
git add admin/ui/src/routes/packages.tsx
git commit -m "feat: add packages tab with QR code panel"
```

---

### Task 6: Plugins + Maps tabs

**Files:**
- Create: `admin/ui/src/routes/plugins.tsx`
- Create: `admin/ui/src/routes/maps.tsx`

- [ ] **Step 1: Write admin/ui/src/routes/plugins.tsx**

```typescript
import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { Upload } from 'lucide-react'

export const Route = createFileRoute('/plugins')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: PluginsPage,
})

interface Plugin { filename: string; size: string }

function PluginsPage() {
  const [plugins, setPlugins] = useState<Plugin[]>([])
  const fileRef = useRef<HTMLInputElement>(null)

  async function load() {
    try {
      const d = await apiJson<{ plugins: Plugin[] }>('/api/plugins')
      setPlugins(d.plugins)
    } catch (e: any) { toast.error(e.message) }
  }

  useEffect(() => { load() }, [])

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    const form = new FormData()
    form.append('file', file)
    try {
      await apiFetch('/api/plugins', { method: 'POST', body: form })
      toast.success(`${file.name} uploaded`)
      load()
    } catch (err: any) { toast.error(err.message) }
  }

  return (
    <Layout>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-xl font-semibold">Plugins</h1>
          <button
            onClick={() => fileRef.current?.click()}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm rounded-md transition-colors"
          >
            <Upload size={14} /> Upload APK
          </button>
          <input ref={fileRef} type="file" accept=".apk,.zip" className="hidden" onChange={handleUpload} />
        </div>
        <div className="rounded-lg border border-zinc-800 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">File</th>
                <th className="px-4 py-3 text-left font-medium">Size</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {plugins.length === 0 && (
                <tr><td colSpan={2} className="px-4 py-8 text-center text-zinc-500">No plugins uploaded</td></tr>
              )}
              {plugins.map(p => (
                <tr key={p.filename} className="bg-zinc-950">
                  <td className="px-4 py-3 font-mono">{p.filename}</td>
                  <td className="px-4 py-3 text-zinc-400">{p.size}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  )
}
```

- [ ] **Step 2: Write admin/ui/src/routes/maps.tsx**

```typescript
import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { Upload } from 'lucide-react'

export const Route = createFileRoute('/maps')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: MapsPage,
})

interface MapSource { provider: string; filename: string; size: string }

function MapsPage() {
  const [maps, setMaps] = useState<MapSource[]>([])
  const [provider, setProvider] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  async function load() {
    try {
      const d = await apiJson<{ maps: MapSource[] }>('/api/maps')
      setMaps(d.maps)
    } catch (e: any) { toast.error(e.message) }
  }

  useEffect(() => { load() }, [])

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    if (!provider.trim()) { toast.error('Enter a provider name first'); return }
    const form = new FormData()
    form.append('file', file)
    try {
      await apiFetch(`/api/maps?provider=${encodeURIComponent(provider)}`, { method: 'POST', body: form })
      toast.success(`${file.name} uploaded to ${provider}`)
      load()
    } catch (err: any) { toast.error(err.message) }
  }

  const grouped = maps.reduce<Record<string, MapSource[]>>((acc, m) => {
    ;(acc[m.provider] ??= []).push(m)
    return acc
  }, {})

  return (
    <Layout>
      <div className="p-6">
        <div className="flex items-center gap-3 mb-6">
          <h1 className="text-xl font-semibold flex-1">Map Sources</h1>
          <input
            type="text"
            value={provider}
            onChange={e => setProvider(e.target.value)}
            placeholder="Provider name"
            className="px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm w-40 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <button
            onClick={() => fileRef.current?.click()}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm rounded-md transition-colors"
          >
            <Upload size={14} /> Upload XML
          </button>
          <input ref={fileRef} type="file" accept=".xml" className="hidden" onChange={handleUpload} />
        </div>

        <div className="space-y-4">
          {Object.entries(grouped).map(([prov, items]) => (
            <div key={prov} className="rounded-lg border border-zinc-800 overflow-hidden">
              <div className="px-4 py-2 bg-zinc-900 text-xs font-semibold text-zinc-400 uppercase tracking-wider">{prov}</div>
              <table className="w-full text-sm">
                <tbody className="divide-y divide-zinc-800">
                  {items.map(m => (
                    <tr key={m.filename} className="bg-zinc-950">
                      <td className="px-4 py-2 font-mono">{m.filename}</td>
                      <td className="px-4 py-2 text-zinc-400">{m.size}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ))}
          {maps.length === 0 && <p className="text-sm text-zinc-500">No map sources loaded</p>}
        </div>
      </div>
    </Layout>
  )
}
```

- [ ] **Step 3: Test both tabs**

Navigate to `/plugins` and `/maps` — tables render, upload buttons work.

- [ ] **Step 4: Commit**

```bash
git add admin/ui/src/routes/plugins.tsx admin/ui/src/routes/maps.tsx
git commit -m "feat: add plugins and maps tabs with file upload"
```

---

### Task 7: Logs tab

**Files:**
- Create: `admin/ui/src/routes/logs.tsx`

- [ ] **Step 1: Write admin/ui/src/routes/logs.tsx**

```typescript
import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { useAuth } from '@/store/auth'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'

export const Route = createFileRoute('/logs')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: LogsPage,
})

const SERVICES = ['takserver_config', 'takserver_messaging', 'takserver_api', 'takserver_retention', 'takdb', 'pkg_server', 'admin']

function LogsPage() {
  const [service, setService] = useState('takserver_config')
  const termRef = useRef<HTMLDivElement>(null)
  const termInstance = useRef<Terminal | null>(null)
  const wsRef = useRef<WebSocket | null>(null)
  const { token } = useAuth()

  useEffect(() => {
    if (!termRef.current) return
    const term = new Terminal({ theme: { background: '#09090b' }, convertEol: true, scrollback: 2000 })
    const fit = new FitAddon()
    term.loadAddon(fit)
    term.open(termRef.current)
    fit.fit()
    termInstance.current = term

    const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(`${proto}://${window.location.host}/api/logs?service=${service}`, [])
    wsRef.current = ws

    ws.onmessage = e => term.writeln(e.data)
    ws.onerror = () => term.writeln('\r\n[connection error]')
    ws.onclose = () => term.writeln('\r\n[disconnected]')

    return () => {
      ws.close()
      term.dispose()
    }
  }, [service])

  return (
    <Layout>
      <div className="p-6 flex flex-col h-full">
        <div className="flex items-center gap-3 mb-4">
          <h1 className="text-xl font-semibold flex-1">Logs</h1>
          <select
            value={service}
            onChange={e => setService(e.target.value)}
            className="px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none"
          >
            {SERVICES.map(s => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>
        <div ref={termRef} className="flex-1 rounded-lg overflow-hidden border border-zinc-800" style={{ minHeight: '500px' }} />
      </div>
    </Layout>
  )
}
```

- [ ] **Step 2: Test**

Navigate to `/logs` — xterm.js terminal renders with dark background, log lines stream from selected service. Changing the dropdown reconnects to the new service.

- [ ] **Step 3: Commit**

```bash
git add admin/ui/src/routes/logs.tsx
git commit -m "feat: add logs tab with xterm.js WebSocket streaming"
```

---

### Task 8: Shell tab

**Files:**
- Create: `admin/ui/src/routes/shell.tsx`

- [ ] **Step 1: Write admin/ui/src/routes/shell.tsx**

```typescript
import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import { toast } from 'sonner'
import { ShieldAlert } from 'lucide-react'

export const Route = createFileRoute('/shell')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: ShellPage,
})

function ShellPage() {
  const [password, setPassword] = useState('')
  const [elevated, setElevated] = useState(false)
  const [loading, setLoading] = useState(false)
  const termRef = useRef<HTMLDivElement>(null)
  const termInstance = useRef<Terminal | null>(null)

  async function elevate(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const data = await apiJson<{ ticket: string }>('/auth/shell-elevate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      })
      setElevated(true)
      openShell(data.ticket)
    } catch (err: any) {
      toast.error(err.message)
    } finally {
      setLoading(false)
    }
  }

  function openShell(ticket: string) {
    if (!termRef.current) return
    const term = new Terminal({ theme: { background: '#09090b' }, cursorBlink: true, convertEol: true })
    const fit = new FitAddon()
    term.loadAddon(fit)
    term.open(termRef.current)
    fit.fit()
    termInstance.current = term

    const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(`${proto}://${window.location.host}/api/shell/ws?t=${ticket}`)
    ws.binaryType = 'arraybuffer'

    ws.onopen = () => term.writeln('Connected to takserver_config\r\n')
    ws.onmessage = e => {
      if (e.data instanceof ArrayBuffer) term.write(new Uint8Array(e.data))
      else term.write(e.data)
    }
    ws.onclose = () => term.writeln('\r\n[session ended]')
    ws.onerror = () => term.writeln('\r\n[connection error]')

    term.onData(data => {
      if (ws.readyState === WebSocket.OPEN) ws.send(data)
    })
  }

  return (
    <Layout>
      <div className="p-6 flex flex-col h-full">
        <h1 className="text-xl font-semibold mb-4">Shell — takserver_config</h1>

        {!elevated && (
          <div className="max-w-sm space-y-4">
            <div className="flex items-start gap-3 p-4 rounded-lg border border-yellow-700/50 bg-yellow-900/20">
              <ShieldAlert size={16} className="text-yellow-400 shrink-0 mt-0.5" />
              <p className="text-sm text-yellow-200">Re-enter your password to unlock shell access. Session expires in 5 minutes.</p>
            </div>
            <form onSubmit={elevate} className="space-y-3">
              <input
                type="password"
                value={password}
                onChange={e => setPassword(e.target.value)}
                placeholder="Your admin password"
                required
                className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <button
                type="submit"
                disabled={loading}
                className="w-full py-2 rounded-md bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium disabled:opacity-50 transition-colors"
              >
                {loading ? 'Verifying…' : 'Unlock shell'}
              </button>
            </form>
          </div>
        )}

        {elevated && (
          <div ref={termRef} className="flex-1 rounded-lg overflow-hidden border border-zinc-800" style={{ minHeight: '500px' }} />
        )}
      </div>
    </Layout>
  )
}
```

- [ ] **Step 2: Test**

Navigate to `/shell` as superadmin — password prompt shown. Enter correct password → terminal opens connected to `takserver_config` bash. Type `ls /opt/tak` and see output.

- [ ] **Step 3: Commit**

```bash
git add admin/ui/src/routes/shell.tsx
git commit -m "feat: add shell tab with xterm.js and password elevation"
```

---

### Task 9: Admin Users tab

**Files:**
- Create: `admin/ui/src/routes/admin-users.tsx`
- Create: `admin/ui/src/routes/admin-users.new.tsx`

- [ ] **Step 1: Write admin/ui/src/routes/admin-users.tsx**

```typescript
import { createFileRoute, redirect, Link } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { UserPlus, Trash2 } from 'lucide-react'

export const Route = createFileRoute('/admin-users')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: AdminUsersPage,
})

interface AdminUser { id: string; username: string; role: string; is_active: boolean; created_at: string }

const ROLE_COLORS: Record<string, string> = {
  superadmin: 'text-purple-400 bg-purple-400/10',
  admin: 'text-blue-400 bg-blue-400/10',
  readonly: 'text-zinc-400 bg-zinc-400/10',
}

function AdminUsersPage() {
  const [users, setUsers] = useState<AdminUser[]>([])

  async function load() {
    try {
      const data = await apiJson<AdminUser[]>('/api/admin-users')
      setUsers(data)
    } catch (e: any) { toast.error(e.message) }
  }

  useEffect(() => { load() }, [])

  async function deactivate(id: string, username: string) {
    if (!confirm(`Deactivate ${username}?`)) return
    try {
      await apiFetch(`/api/admin-users/${id}`, { method: 'DELETE' })
      toast.success(`${username} deactivated`)
      load()
    } catch (e: any) { toast.error(e.message) }
  }

  return (
    <Layout>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-xl font-semibold">Admin Users</h1>
          <Link to="/admin-users/new" className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm rounded-md transition-colors">
            <UserPlus size={14} /> New Admin
          </Link>
        </div>
        <div className="rounded-lg border border-zinc-800 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">Username</th>
                <th className="px-4 py-3 text-left font-medium">Role</th>
                <th className="px-4 py-3 text-left font-medium">Status</th>
                <th className="px-4 py-3 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {users.map(u => (
                <tr key={u.id} className="bg-zinc-950 hover:bg-zinc-900/50">
                  <td className="px-4 py-3 font-mono">{u.username}</td>
                  <td className="px-4 py-3">
                    <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${ROLE_COLORS[u.role] ?? ''}`}>{u.role}</span>
                  </td>
                  <td className="px-4 py-3">
                    <span className={`text-xs ${u.is_active ? 'text-green-400' : 'text-zinc-500'}`}>{u.is_active ? 'active' : 'inactive'}</span>
                  </td>
                  <td className="px-4 py-3 flex justify-end">
                    <button onClick={() => deactivate(u.id, u.username)} className="p-1.5 rounded hover:bg-zinc-800 text-red-400"><Trash2 size={14} /></button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  )
}
```

- [ ] **Step 2: Write admin/ui/src/routes/admin-users.new.tsx**

```typescript
import { createFileRoute, redirect, useNavigate } from '@tanstack/react-router'
import { useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'

export const Route = createFileRoute('/admin-users/new')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: NewAdminUserPage,
})

function NewAdminUserPage() {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [role, setRole] = useState<'admin' | 'readonly'>('admin')
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (password.length < 12) { toast.error('Password must be at least 12 characters'); return }
    setLoading(true)
    try {
      await apiJson('/api/admin-users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password, role }),
      })
      toast.success(`${username} created`)
      navigate({ to: '/admin-users' })
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <Layout>
      <div className="p-6 max-w-sm">
        <h1 className="text-xl font-semibold mb-6">New Admin User</h1>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1">
            <label className="text-sm text-zinc-300">Username</label>
            <input type="text" value={username} onChange={e => setUsername(e.target.value)} required
              className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
          </div>
          <div className="space-y-1">
            <label className="text-sm text-zinc-300">Password (min 12 chars)</label>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)} required minLength={12}
              className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
          </div>
          <div className="space-y-1">
            <label className="text-sm text-zinc-300">Role</label>
            <select value={role} onChange={e => setRole(e.target.value as any)}
              className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none">
              <option value="admin">admin</option>
              <option value="readonly">readonly</option>
            </select>
          </div>
          <button type="submit" disabled={loading}
            className="w-full py-2 rounded-md bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium disabled:opacity-50 transition-colors">
            {loading ? 'Creating…' : 'Create'}
          </button>
        </form>
      </div>
    </Layout>
  )
}
```

- [ ] **Step 3: Test**

Navigate to `/admin-users` as superadmin — list of admin users shown with role badges. Navigate to `/admin-users/new`, create a new admin user, verify it appears in the list.

- [ ] **Step 4: Commit**

```bash
git add admin/ui/src/routes/admin-users.tsx admin/ui/src/routes/admin-users.new.tsx
git commit -m "feat: add admin users management tab"
```

---

### Task 10: Production build + Dockerfile integration

**Files:**
- Modify: `admin/Dockerfile` (verify two-stage build)
- Modify: `docker-compose.yml` (verify admin build context)

- [ ] **Step 1: Build UI and verify output**

```bash
cd admin/ui
pnpm build
ls dist/
```

Expected: `dist/index.html`, `dist/assets/` directory with JS/CSS chunks.

- [ ] **Step 2: Build full Docker image**

```bash
cd /home/ndukve/IdeaProjects/TAK
docker compose build admin
```

Expected: build completes, UI dist copied into image.

- [ ] **Step 3: Start and verify admin panel serves UI**

```bash
docker compose up -d admin
curl -s http://localhost:8889/ | head -5
```

Expected: HTML response starting with `<!doctype html>`.

- [ ] **Step 4: Full smoke test**

Open `http://localhost:8889` in a browser. Verify:
- Login page renders
- Login with `admin` / `ADMIN_FIRST_PASS` succeeds
- Dashboard shows service health cards
- Users, Packages, Plugins, Maps, Logs tabs all load
- Shell tab shows password prompt (superadmin only)
- Admin Users tab shows current admin account

- [ ] **Step 5: Commit**

```bash
git add admin/
git commit -m "feat: complete TAK admin panel - backend + frontend integrated"
```
