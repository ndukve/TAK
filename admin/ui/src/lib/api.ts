import { useAuth } from '@/store/auth'

const BASE = ''  // same origin in prod; Vite proxy in dev

// The refresh cookie is single-use (rotated on every /auth/refresh call, with
// reuse treated as token theft and the whole session revoked) — if two 401s
// land at once, each firing its own refresh would make the second one look
// like a replay attack. Share one in-flight refresh across concurrent callers.
let refreshPromise: Promise<string | null> | null = null

export async function refreshToken(): Promise<string | null> {
  if (refreshPromise) return refreshPromise
  refreshPromise = (async () => {
    const res = await fetch(`${BASE}/auth/refresh`, { method: 'POST', credentials: 'include' })
    if (!res.ok) return null
    const data = await res.json()
    const payload = JSON.parse(atob(data.access_token.split('.')[1]))
    useAuth.getState().setToken(data.access_token, payload.role, payload.username, payload.auth_provider)
    return data.access_token
  })()
  try {
    return await refreshPromise
  } finally {
    refreshPromise = null
  }
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

  if (res.status === 403) {
    try {
      const body = await res.clone().json()
      if (body.detail === 'password_expired') {
        useAuth.getState().setPasswordExpired(true)
      }
    } catch {
      // non-JSON or unreadable body — not a password-expired response, ignore
    }
  }

  return res
}

export function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e)
}

export async function apiJson<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await apiFetch(path, init)
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }))
    throw new Error(err.detail ?? res.statusText)
  }
  return res.json()
}

// Plain <a href> downloads don't carry the Authorization header our JWT auth
// needs (browsers only attach that via explicit fetch calls), so protected
// download endpoints 401 on a normal link click. Fetch authenticated via
// apiFetch, then hand the browser a blob URL to save instead.
export async function downloadFile(path: string, filename: string): Promise<void> {
  const res = await apiFetch(path)
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }))
    throw new Error(err.detail ?? res.statusText)
  }
  const blob = await res.blob()
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}
