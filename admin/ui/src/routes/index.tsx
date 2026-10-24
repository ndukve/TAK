import { createFileRoute, redirect, Link } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { cn } from '@/lib/utils'
import { Skeleton } from '@/components/Skeleton'
import { Icon } from '@/components/ui/icon'
import { LiveMapWidget } from '@/components/LiveMapWidget'
import { StatusPill } from '@/components/StatusPill'

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

function formatAge(seconds: number): string {
  if (seconds < 1) return 'just now'
  if (seconds < 60) return `${Math.floor(seconds)}s ago`
  return `${Math.floor(seconds / 60)}m ago`
}

/** Ticking "Xs ago" label off a fixed fetch timestamp — evidence freshness,
    not a fake decoration: this is genuinely how old the last successful poll is. */
function FreshnessLabel({ since }: { since: number | null }) {
  const [, forceTick] = useState(0)
  useEffect(() => {
    const id = setInterval(() => forceTick(n => n + 1), 1000)
    return () => clearInterval(id)
  }, [])
  if (since === null) return null
  return (
    <span className="text-[10px] text-zinc-500 flex items-center gap-1.5">
      <span className="w-1 h-1 rounded-full bg-green-500 animate-pulse" />
      AS OF {formatAge((Date.now() - since) / 1000)}
    </span>
  )
}

function DashboardPage() {
  const { role } = useAuth()
  const [services, setServices] = useState<ServiceState[]>([])
  const [system, setSystem] = useState<SystemStats | null>(null)
  const [fetchedAt, setFetchedAt] = useState<number | null>(null)

  async function load() {
    try {
      const data = await apiJson<{ services: ServiceState[]; system: SystemStats }>('/api/health')
      setServices(data.services)
      setSystem(data.system)
      setFetchedAt(Date.now())
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

  const downServices = services.filter(s => s.status !== 'running')
  const attentionCount = downServices.length + (diskState !== 'ok' ? 1 : 0)
  const nominal = system !== null && attentionCount === 0

  return (
    <Layout>
      <div className="p-4 md:p-5">
        <PageHeader title="Dashboard" />

        {system && (
          <div className={cn(
            'mb-4 flex flex-wrap items-center gap-x-4 gap-y-1 rounded-lg border px-4 py-2.5 text-sm',
            nominal ? 'border-green-500/35' : 'border-yellow-500/35'
          )}>
            <span className={cn('size-2 rounded-full', nominal ? 'bg-green-500' : 'bg-yellow-500')} />
            <span className={cn('font-medium', nominal ? 'text-green-600 dark:text-green-400' : 'text-yellow-600 dark:text-yellow-400')}>{nominal ? 'Nominal' : 'Needs attention'}</span>
            <span className="text-xs text-zinc-500">
              {nominal
                ? `All ${services.length} services running.`
                : `${attentionCount} of ${services.length + (diskState !== 'ok' ? 1 : 0)} tracked signals need attention: ${
                    downServices[0] ? `${downServices[0].name} is ${downServices[0].status}` : 'disk usage is elevated'
                  }.`}
            </span>
            <span className="ml-auto"><FreshnessLabel since={fetchedAt} /></span>
          </div>
        )}

        <div className="mb-4 grid grid-cols-[repeat(auto-fit,minmax(10.5rem,1fr))] gap-px overflow-hidden rounded-lg border border-zinc-200 bg-zinc-200 dark:border-white/10 dark:bg-white/10">
          {system ? (
            <>
              <SystemStatCard icon="cpu-line" label="CPU" value={system.cpu_percent !== null ? `${system.cpu_percent}%` : '—'} />
              <SystemStatCard icon="ram-line" label="RAM" value={system.mem_used_mb !== null && system.mem_total_mb !== null ? `${(system.mem_used_mb / 1024).toFixed(1)} / ${(system.mem_total_mb / 1024).toFixed(1)} GB` : 'N/A'} />
              <SystemStatCard icon="hard-drive-2-line" label="Disk" value={diskAvailable ? `${system.disk_used_gb!.toFixed(1)} / ${system.disk_total_gb!.toFixed(1)} GB` : 'N/A'} state={diskState} />
              <SystemStatCard icon="time-line" label="Uptime" value={formatUptime(system.uptime_seconds)} />
              <SystemStatCard icon="pulse-line" label="Load avg" value={system.load_avg ? system.load_avg.map(n => n.toFixed(2)).join(' / ') : 'N/A'} />
              <SystemStatCard icon="arrow-up-down-line" label="Network" value={`↓${formatBytesPerSec(system.net_rx_bytes_per_sec)} ↑${formatBytesPerSec(system.net_tx_bytes_per_sec)}`} />
            </>
          ) : (
            Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="bg-white px-4 py-2.5 dark:bg-zinc-900">
                <Skeleton className="h-2.5 w-10" />
                <Skeleton className="mt-2 h-3.5 w-20" />
              </div>
            ))
          )}
        </div>

        <div className="mb-4 grid gap-4 lg:grid-cols-3">
          <section className="min-w-0 rounded-lg border border-zinc-200 bg-white dark:border-white/10 dark:bg-zinc-900 lg:col-span-2">
            <header className="border-b border-zinc-200 px-4 py-2 text-sm font-medium dark:border-white/10">Services</header>
            <div className="overflow-x-auto">
              <div className="grid min-w-[480px] grid-cols-[1.6fr_1fr_1fr_1fr] border-b border-zinc-200 px-4 py-1.5 text-xs text-zinc-500 dark:border-white/10">
                <span>Service</span><span>Status</span><span>Deployment</span><span>Actions</span>
              </div>
              {services.map(s => (
                <ServiceRow key={s.name} service={s} />
              ))}
            </div>
          </section>
          {services.length > 0 && (
            <section className="min-w-0 rounded-lg border border-zinc-200 bg-white dark:border-white/10 dark:bg-zinc-900">
              <header className="border-b border-zinc-200 px-4 py-2 text-sm font-medium dark:border-white/10">Service topology</header>
              <ServiceTopology services={services} />
            </section>
          )}
        </div>

        {role !== 'readonly' && (
          <section className="rounded-lg border border-zinc-200 bg-white dark:border-white/10 dark:bg-zinc-900">
            <header className="flex items-center justify-between border-b border-zinc-200 px-4 py-2 dark:border-white/10">
              <h2 className="text-sm font-medium">Live Map</h2>
              <Link to="/live-map" className="text-xs text-accent-ring hover:underline">Open full map →</Link>
            </header>
            <LiveMapWidget height="420px" pollMs={8000} />
          </section>
        )}
      </div>
    </Layout>
  )
}

function SystemStatCard({ icon, label, value, state = 'ok' }: { icon: string; label: string; value: string; state?: 'ok' | 'warn' | 'critical' }) {
  const textClass = state === 'critical' ? 'text-red-600 dark:text-red-400' : state === 'warn' ? 'text-yellow-600 dark:text-yellow-400' : 'text-zinc-900 dark:text-zinc-100'
  return (
    <div className="flex min-w-0 items-center gap-3 bg-white px-4 py-2.5 dark:bg-zinc-900">
      <span className="flex size-8 shrink-0 items-center justify-center rounded-md border border-zinc-200 bg-zinc-100 dark:border-white/10 dark:bg-white/[0.05]">
        <Icon name={icon} size={16} className={state === 'ok' ? 'text-zinc-500 dark:text-zinc-400' : textClass} />
      </span>
      <div className="min-w-0">
        <p className="text-xs text-zinc-500">{label}</p>
        <p title={value} className={cn('mt-0.5 truncate text-sm font-medium', textClass)}>{value}</p>
      </div>
    </div>
  )
}

function ServiceTopology({ services }: { services: ServiceState[] }) {
  return (
    <div className="p-4 overflow-x-auto">
      <div className="flex flex-col items-center min-w-[560px]">
        <div className="rounded-md border border-zinc-300 dark:border-white/20 px-4 py-2 text-center">
          <div className="text-sm font-semibold">nginx · admin api</div>
          <div className="text-[10px] text-zinc-500 mt-0.5">managed host</div>
        </div>
        <div className="w-px h-5 bg-zinc-300 dark:bg-white/20" />
        <div className="relative w-[92%] h-px bg-zinc-300 dark:bg-white/20" />
        <div className="flex justify-between w-[92%] gap-2">
          {services.map(s => {
            const running = s.status === 'running'
            return (
              <div key={s.name} className="flex flex-col items-center flex-1">
                <div className="w-px h-4 bg-zinc-300 dark:bg-white/20" />
                <div className="rounded-md border border-zinc-200 dark:border-white/10 bg-white dark:bg-zinc-900 px-2 py-2 text-center w-full">
                  <span className={cn('inline-block size-1.5 rounded-full mb-1.5', running ? 'bg-green-500' : 'bg-red-500')} />
                  <div className="text-[10px] font-medium truncate" title={s.name}>{s.name.replace('takserver_', '')}</div>
                  <div className="text-[9px] text-zinc-500 mt-0.5">{s.status}</div>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}

function ServiceRow({ service }: { service: ServiceState }) {
  const { role } = useAuth()
  const running = service.status === 'running'
  const loggableName = service.name.split(':')[0]
  const canViewLogs = role === 'superadmin' && LOGGABLE_SERVICES.has(loggableName)

  return (
    <div className="grid grid-cols-[1.6fr_1fr_1fr_1fr] min-w-[480px] items-center px-4 py-2 border-b border-zinc-100 dark:border-white/5 last:border-0">
      <span title={service.name} className="text-sm truncate pr-2">{service.name}</span>
      <span><StatusPill text={service.status} tone={running ? 'ok' : 'bad'} /></span>
      <span className="text-xs text-zinc-500">{running ? 'applied' : 'unconfirmed'}</span>
      <span>
        {canViewLogs && (
          <Link to="/logs" search={{ service: loggableName }} className="text-xs text-accent-ring hover:underline">
            View logs →
          </Link>
        )}
      </span>
    </div>
  )
}
