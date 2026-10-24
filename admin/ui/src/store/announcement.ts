import { create } from 'zustand'

interface AnnouncementState {
  message: string | null
  dismissed: boolean
  announce: (message: string | null) => void
  dismiss: () => void
}

// The info bar above the header. Anything that wants the operator to see a notice calls announce(); dismissing hides it until the next one.
export const useAnnouncement = create<AnnouncementState>((set) => ({
  message: import.meta.env.DEV ? 'Local dev preview: the data shown here is not from a real TAK Server.' : null,
  dismissed: false,
  announce: (message) => set({ message, dismissed: false }),
  dismiss: () => set({ dismissed: true }),
}))
