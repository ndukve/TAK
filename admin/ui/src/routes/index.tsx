import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { CheckCircle, XCircle } from 'lucide-react'
import { cn } from '@/lib/utils'

export const Route = createFileRoute('/')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: DashboardPage,
})

interface ServiceState {
  name: string
  status: string
  health: string
}

function DashboardPage() {
  const [services, setServices] = useState<ServiceState[]>([])

  async function load() {
    try {
      const data = await apiJson<{ services: ServiceState[] }>('/api/health')
      setServices(data.services)
    } catch {}
  }

  useEffect(() => {
    load()
    const id = setInterval(load, 5000)
    return () => clearInterval(id)
  }, [])

  return (
    <Layout>
      <div className="p-6">
        <h1 className="text-xl font-semibold mb-6">Dashboard</h1>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {services.map(s => (
            <ServiceCard key={s.name} service={s} />
          ))}
        </div>
      </div>
    </Layout>
  )
}

function ServiceCard({ service }: { service: ServiceState }) {
  const running = service.status === 'running'
  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs font-mono text-zinc-400">{service.name}</span>
        {running
          ? <CheckCircle size={14} className="text-green-500" />
          : <XCircle size={14} className="text-red-500" />
        }
      </div>
      <span className={cn('text-sm font-medium', running ? 'text-green-400' : 'text-red-400')}>
        {service.status}
      </span>
    </div>
  )
}
