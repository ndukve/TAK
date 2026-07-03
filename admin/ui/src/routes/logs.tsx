import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { useAuth } from '@/store/auth'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'

export const Route = createFileRoute('/logs')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role === 'field') throw redirect({ to: '/packages' })
  },
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
  const [service, setService] = useState('takserver_config')
  const termRef = useRef<HTMLDivElement>(null)
  const wsRef = useRef<WebSocket | null>(null)
  const { token } = useAuth()

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

    const connect = () => {
      const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
      const ws = new WebSocket(
        `${proto}://${window.location.host}/api/logs?service=${service}&token=${token}`
      )
      wsRef.current = ws

      ws.onmessage = (e) => term.writeln(formatLogLine(e.data))
      ws.onerror = () => term.writeln('\r\n[connection error]')
      ws.onclose = (e) => {
        if (closedByUs) return
        if (e.code === 4401) {
          term.writeln('\r\n[unauthorized — token invalid]')
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
  }, [service, token])

  return (
    <Layout>
      <div className="p-6 flex flex-col h-full">
        <div className="flex items-center gap-3 mb-4">
          <h1 className="text-xl font-semibold flex-1">Logs</h1>
          <select
            value={service}
            onChange={(e) => setService(e.target.value)}
            className="px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none"
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
          className="flex-1 rounded-lg overflow-hidden border border-zinc-800"
          style={{ minHeight: '500px' }}
        />
      </div>
    </Layout>
  )
}
