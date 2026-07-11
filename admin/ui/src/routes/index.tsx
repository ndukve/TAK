import { createFileRoute, redirect, Link } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { CheckCircle, XCircle, Cpu, MemoryStick, HardDrive, Clock, Activity, Network, type LucideIcon } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Skeleton } from '@/components/Skeleton'
import { HudCorners } from '@/components/HudCorners'
import { LiveMapWidget } from '@/components/LiveMapWidget'

const LOGGABLE_SERVICES = new Set([
  'takserver_config', 'takserver_messaging', 'takserver_api',
  'takserver_retention', 'takserver_pluginmanager', 'takdb', 'admin',
])

export const Route = createFileRoute('/')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role === 'field') throw redirect({ to: '/packages' })
  },
  component: DashboardPage,
})

interface ServiceState {
  name: string
  status: string
  health: string
}

interface CertInfo {
  name: string
  expires_at: string
  days_remaining: number
}

interface SystemStats {
  cpu_percent: number | null
  mem_used_mb: number | null
  mem_total_mb: number | null
  disk_used_gb: number | null
  disk_total_gb: number | null
  uptime_seconds: number | null
  load_avg: [number, number, number] | null
  net_rx_bytes_per_sec: number | null
  net_tx_bytes_per_sec: number | null
  certs: CertInfo[]
}

function formatUptime(seconds: number | null): string {
  if (seconds === null) return '—'
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

function formatBytesPerSec(bytes: number | null): string {
  if (bytes === null) return '—'
  if (bytes < 1024) return `${bytes.toFixed(0)} B/s`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB/s`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB/s`
}

function DashboardPage() {
  const { role } = useAuth()
  const [services, setServices] = useState<ServiceState[]>([])
  const [system, setSystem] = useState<SystemStats | null>(null)

  async function load() {
    try {
      const data = await apiJson<{ services: ServiceState[]; system: SystemStats }>('/api/health')
      setServices(data.services)
      setSystem(data.system)
    } catch {
      // health endpoint unreachable — leave prior state, next poll retries
    }
  }

  useEffect(() => {
    load()
    const id = setInterval(load, 5000)
    return () => clearInterval(id)
  }, [])

  const diskAvailable = system?.disk_used_gb !== null && system?.disk_total_gb !== null
  const diskPercent = system && diskAvailable ? (system.disk_used_gb! / system.disk_total_gb!) * 100 : 0
  const diskState = !diskAvailable ? 'ok' : diskPercent >= 95 ? 'critical' : diskPercent >= 85 ? 'warn' : 'ok'

  return (
    <Layout>
      <div className="p-8 max-w-[1600px]">
        <PageHeader title="Dashboard" />

        <div className="flex flex-nowrap gap-3 pt-1 pb-3 mb-3 overflow-x-auto hud-enter">
          {system ? (
            <>
              <SystemStatCard icon={Cpu} label="CPU" value={system.cpu_percent !== null ? `${system.cpu_percent}%` : '—'} />
              <SystemStatCard icon={MemoryStick} label="RAM" value={system.mem_used_mb !== null && system.mem_total_mb !== null ? `${(system.mem_used_mb / 1024).toFixed(1)} / ${(system.mem_total_mb / 1024).toFixed(1)} GB` : 'N/A'} />
              <SystemStatCard icon={HardDrive} label="Disk" value={diskAvailable ? `${system.disk_used_gb!.toFixed(1)} / ${system.disk_total_gb!.toFixed(1)} GB` : 'N/A'} state={diskState} />
              <SystemStatCard icon={Clock} label="Uptime" value={formatUptime(system.uptime_seconds)} />
              <SystemStatCard icon={Activity} label="Load avg" value={system.load_avg ? system.load_avg.map(n => n.toFixed(2)).join(' / ') : 'N/A'} />
              <SystemStatCard icon={Network} label="Network" value={`↓${formatBytesPerSec(system.net_rx_bytes_per_sec)} ↑${formatBytesPerSec(system.net_tx_bytes_per_sec)}`} />
            </>
          ) : (
            Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="rounded-md border border-zinc-200 dark:border-white/10 bg-white dark:bg-[#111113] p-2.5 hud-card flex-1 min-w-[120px] h-24">
                <div className="flex items-start justify-between mb-1.5">
                  <Skeleton className="h-2 w-8" />
                  <Skeleton className="w-5 h-5 rounded" />
                </div>
                <Skeleton className="h-3.5 w-20" />
              </div>
            ))
          )}
        </div>
        {system && <CertList certs={system.certs} />}

        <h2 className="hud-label text-sm font-semibold text-zinc-600 dark:text-zinc-400 mb-3">Services</h2>
        <div className="flex flex-nowrap gap-3 pt-1 pb-3 mb-3 overflow-x-auto hud-enter hud-enter-delay-1">
          {services.map(s => (
            <ServiceCard key={s.name} service={s} />
          ))}
        </div>

        {role !== 'readonly' && (
          <div>
            <div className="flex items-center justify-between mb-3">
              <h2 className="hud-label text-sm font-semibold text-zinc-600 dark:text-zinc-400">Live Map</h2>
              <Link to="/live-map" className="text-xs text-accent-ring hover:underline">Open full map →</Link>
            </div>
            <LiveMapWidget height="480px" pollMs={8000} />
          </div>
        )}
      </div>
    </Layout>
  )
}

function SystemStatCard({ icon: Icon, label, value, state = 'ok' }: { icon: LucideIcon; label: string; value: string; state?: 'ok' | 'warn' | 'critical' }) {
  const badgeClass = state === 'critical' ? 'border-red-300 dark:border-red-800 bg-red-100 dark:bg-red-500/10' : state === 'warn' ? 'border-yellow-300 dark:border-yellow-800 bg-yellow-100 dark:bg-yellow-500/10' : 'border-zinc-300 dark:border-white/10 bg-zinc-200/50 dark:bg-white/[0.04]'
  const textClass = state === 'critical' ? 'text-red-600 dark:text-red-400' : state === 'warn' ? 'text-yellow-600 dark:text-yellow-400' : 'text-zinc-800 dark:text-zinc-200'
  return (
    <div className="hud-frame rounded-md border border-zinc-200 dark:border-white/10 bg-white dark:bg-[#111113] p-2.5 hud-card flex-1 min-w-[120px] h-24 flex flex-col justify-between">
      <HudCorners />
      <div className="flex items-start justify-between">
        <span className="text-[9px] font-semibold tracking-wider text-zinc-500 uppercase">{label}</span>
        <div className={cn('w-5 h-5 rounded border flex items-center justify-center shrink-0', badgeClass)}>
          <Icon size={11} className={textClass} />
        </div>
      </div>
      <p className={cn('text-xs font-medium font-mono truncate', textClass)}>{value}</p>
    </div>
  )
}

function CertList({ certs }: { certs: CertInfo[] }) {
  if (certs.length === 0) return null
  return (
    <div className="rounded-md border border-zinc-200 dark:border-white/10 bg-white dark:bg-[#111113] p-4 mb-6 hud-card">
      <span className="text-[10px] font-semibold tracking-wider text-zinc-500 uppercase">Certificates</span>
      <div className="mt-3 space-y-2">
        {certs.map(c => {
          const state = c.days_remaining < 7 ? 'critical' : c.days_remaining < 30 ? 'warn' : 'ok'
          const textClass = state === 'critical' ? 'text-red-600 dark:text-red-400' : state === 'warn' ? 'text-yellow-600 dark:text-yellow-400' : 'text-green-600 dark:text-green-400'
          return (
            <div key={c.name} className="flex items-center justify-between text-sm">
              <span className="font-mono text-zinc-700 dark:text-zinc-300">{c.name}</span>
              <span className="text-zinc-500">{c.expires_at}</span>
              <span className={cn('font-mono text-xs', textClass)}>{c.days_remaining}d remaining</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}

function ServiceCard({ service }: { service: ServiceState }) {
  const { role } = useAuth()
  const running = service.status === 'running'
  const loggableName = service.name.split(':')[0]
  const canViewLogs = role === 'superadmin' && LOGGABLE_SERVICES.has(loggableName)

  const badge = (
    <div className={cn(
      'w-5 h-5 rounded border flex items-center justify-center shrink-0',
      running ? 'border-green-300 dark:border-green-800 bg-green-100 dark:bg-green-500/10' : 'border-red-300 dark:border-red-800 bg-red-100 dark:bg-red-500/10',
      canViewLogs && 'hover:ring-2 hover:ring-accent-ring cursor-pointer transition-shadow'
    )}>
      {running
        ? <CheckCircle size={11} className="text-green-600 dark:text-green-500" />
        : <XCircle size={11} className="text-red-600 dark:text-red-500" />
      }
    </div>
  )

  return (
    <div className="hud-frame rounded-md border border-zinc-200 dark:border-white/10 bg-white dark:bg-[#111113] p-2.5 hud-card flex-1 min-w-[120px] h-24 flex flex-col justify-between">
      <HudCorners />
      <div className="flex items-start justify-between">
        <span className="text-[9px] font-semibold tracking-wider text-zinc-500 uppercase">Service</span>
        {canViewLogs
          ? <Link to="/logs" search={{ service: loggableName }} title="View logs" aria-label={`View logs for ${service.name}`}>{badge}</Link>
          : badge
        }
      </div>
      <p className="text-xs font-medium text-zinc-800 dark:text-zinc-200 font-mono truncate">{service.name}</p>
      <div className="border-t border-zinc-200 dark:border-white/10 pt-1.5">
        <span className={cn('text-[11px] font-medium', running ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400')}>
          {service.status}
        </span>
      </div>
    </div>
  )
}
