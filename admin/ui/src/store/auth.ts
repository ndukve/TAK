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
