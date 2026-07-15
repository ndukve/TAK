import { createFileRoute, redirect } from '@tanstack/react-router'
import { Layout } from '@/components/Layout'
import { useAuth } from '@/store/auth'

export const Route = createFileRoute('/shell')({
  beforeLoad: () => {
    const { token, role, authProvider } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin' || authProvider !== 'local') throw redirect({ to: '/' })
  },
  component: ShellPage,
})

// Actual terminal UI lives in <ShellSession>, mounted once at the app root
// (see main.tsx) so it survives navigating away and back. This route only
// needs to exist for the guard above and to render the normal page chrome —
// ShellSession positions itself over this page's content area via CSS.
function ShellPage() {
  return <Layout>{null}</Layout>
}
