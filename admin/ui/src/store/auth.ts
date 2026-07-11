import { create } from 'zustand'

interface AuthState {
  token: string | null
  role: string | null
  username: string | null
  passwordExpired: boolean
  setToken: (token: string, role: string, username: string) => void
  setPasswordExpired: (v: boolean) => void
  clear: () => void
}

// Memory-only — the access token never touches localStorage/sessionStorage,
// so an XSS payload can't read it out of persisted storage. It's cheap to
// lose on reload since main.tsx trades the httponly refresh cookie for a
// fresh one before the router mounts.
export const useAuth = create<AuthState>()((set) => ({
  token: null,
  role: null,
  username: null,
  passwordExpired: false,
  setToken: (token, role, username) => set({ token, role, username }),
  setPasswordExpired: (v) => set({ passwordExpired: v }),
  clear: () => set({ token: null, role: null, username: null, passwordExpired: false }),
}))
