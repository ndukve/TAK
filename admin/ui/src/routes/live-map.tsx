import { createFileRoute, redirect } from '@tanstack/react-router'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { LiveMapWidget } from '@/components/LiveMapWidget'
import { useAuth } from '@/store/auth'

export const Route = createFileRoute('/live-map')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role === 'field' || role === 'readonly') throw redirect({ to: '/' })
  },
  component: LiveMapPage,
})

function LiveMapPage() {
  return (
    <Layout>
      <div className="p-6">
        <PageHeader title="Live Map" />
        <LiveMapWidget height="70vh" showControls pollMs={5000} />
      </div>
    </Layout>
  )
}
