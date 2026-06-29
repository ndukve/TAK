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
