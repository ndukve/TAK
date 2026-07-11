import { createFileRoute, redirect, useSearch } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { useAuth } from '@/store/auth'
import { apiFetch } from '@/lib/api'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'

export const Route = createFileRoute('/logs')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role === 'field') throw redirect({ to: '/packages' })
  },
  validateSearch: (search: Record<string, unknown>): { service?: string } => ({
    service: typeof search.service === 'string' ? search.service : undefined,
  }),
  component: LogsPage,
})

const SERVICES = [
  'takserver_config',
  'takserver_messaging',
  'takserver_api',
  'takserver_retention',
  'takserver_pluginmanager',
  'takdb',
  'pkg_server',
  'admin',
]

// Docker --timestamps prefixes each line with an RFC3339Nano UTC timestamp,
// e.g. "2026-07-02T11:40:25.123456789Z message". Reformat to the viewer's
// local time as "YYYY-MM-DD HH:MM:SS TZ  message".
const TS_RE = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.\d+)?Z (.*)$/s

function formatLogLine(raw: string): string {
  const m = raw.match(TS_RE)
  if (!m) return raw
  const [, isoSec, rest] = m
  const date = new Date(isoSec + 'Z')
  if (Number.isNaN(date.getTime())) return raw
  const pad = (n: number) => String(n).padStart(2, '0')
  const stamp = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
  const tz = new Intl.DateTimeFormat('en-US', { timeZoneName: 'short' })
    .formatToParts(date).find((p) => p.type === 'timeZoneName')?.value ?? ''
  return `${stamp} ${tz}  ${rest}`
}

function LogsPage() {
  const search = useSearch({ from: '/logs' })
  const [service, setService] = useState(
    search.service && SERVICES.includes(search.service) ? search.service : 'takserver_config'
  )
  const termRef = useRef<HTMLDivElement>(null)
  const wsRef = useRef<WebSocket | null>(null)

  useEffect(() => {
    if (!termRef.current) return

    const term = new Terminal({
      theme: { background: '#09090b' },
      convertEol: true,
      scrollback: 2000,
    })
    const fit = new FitAddon()
    term.loadAddon(fit)
    term.open(termRef.current)
    fit.fit()

    let closedByUs = false
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null

    // WebSocket can't send an Authorization header, so the access token can't
    // ride the handshake directly. Mint a short-lived, single-use ticket over
    // an authenticated fetch (real JWT in the header, never in a URL) and put
    // only that ticket in the WS query string.
    const connect = async () => {
      let ticket: string
      try {
        const res = await apiFetch('/auth/ws-ticket', { method: 'POST' })
        if (!res.ok) throw new Error('ticket request failed')
        ;({ ticket } = await res.json())
      } catch {
        term.writeln('\r\n[unable to authenticate — retrying in 2s]')
        reconnectTimer = setTimeout(connect, 2000)
        return
      }

      const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
      const ws = new WebSocket(
        `${proto}://${window.location.host}/api/logs?service=${service}&ticket=${ticket}`
      )
      wsRef.current = ws

      ws.onmessage = (e) => term.writeln(formatLogLine(e.data))
      ws.onerror = () => term.writeln('\r\n[connection error]')
      ws.onclose = (e) => {
        if (closedByUs) return
        if (e.code === 4401) {
          term.writeln('\r\n[unauthorized — ticket invalid or expired]')
          return
        }
        term.writeln('\r\n[disconnected — reconnecting in 2s]')
        reconnectTimer = setTimeout(connect, 2000)
      }
    }
    connect()

    return () => {
      closedByUs = true
      if (reconnectTimer) clearTimeout(reconnectTimer)
      wsRef.current?.close()
      term.dispose()
    }
  }, [service])

  return (
    <Layout>
      <div className="p-6 flex flex-col h-full">
        <PageHeader title="Logs" />
        <div className="flex items-center gap-3 mb-4">
          <select
            value={service}
            onChange={(e) => setService(e.target.value)}
            className="px-3 py-2 rounded-md bg-zinc-200 dark:bg-[#1a1a1d] border border-zinc-300 dark:border-white/10 text-zinc-900 dark:text-white text-sm focus:outline-none"
          >
            {SERVICES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </div>
        <div
          ref={termRef}
          className="flex-1 rounded-md overflow-hidden border border-zinc-200 dark:border-white/10"
          style={{ minHeight: '500px' }}
        />
      </div>
    </Layout>
  )
}
