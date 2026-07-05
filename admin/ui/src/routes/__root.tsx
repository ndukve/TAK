import { createRootRoute, Outlet, redirect } from '@tanstack/react-router'
import { useAuth } from '@/store/auth'
import { Toaster } from 'sonner'

export const Route = createRootRoute({
  component: () => (
    <>
      <Outlet />
      <Toaster richColors position="bottom-right" duration={3000} />
    </>
  ),
})
