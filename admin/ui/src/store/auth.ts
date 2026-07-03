import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface AuthState {
  token: string | null
  role: string | null
  passwordExpired: boolean
  setToken: (token: string, role: string) => void
  setPasswordExpired: (v: boolean) => void
  clear: () => void
}

export const useAuth = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      role: null,
      passwordExpired: false,
      setToken: (token, role) => set({ token, role }),
      setPasswordExpired: (v) => set({ passwordExpired: v }),
      clear: () => set({ token: null, role: null, passwordExpired: false }),
    }),
    { name: 'tak-admin-auth' }
  )
)
