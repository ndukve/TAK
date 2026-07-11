import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import { routeTree } from './routeTree.gen'
import { useBranding } from './store/branding'
import { refreshToken } from './lib/api'
import { ShellSession } from './components/ShellSession'
import './index.css'
import './store/theme'

useBranding.getState().fetchBranding()

// One-time cleanup: earlier builds persisted the access token to localStorage
// under this key via zustand's persist middleware. Remove any leftover token
// from prior sessions now that storage is memory-only.
localStorage.removeItem('tak-admin-auth')

const router = createRouter({ routeTree })

// The access token is memory-only (store/auth.ts) and starts null on every
// page load. Trade the httponly refresh cookie for a fresh one before the
// router's beforeLoad guards run, so a reload doesn't look like a logout.
refreshToken().finally(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <RouterProvider router={router} />
      <ShellSession />
    </StrictMode>
  )
})
