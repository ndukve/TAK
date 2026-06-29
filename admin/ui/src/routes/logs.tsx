import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { useAuth } from '@/store/auth'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'

export const Route = createFileRoute('/logs')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
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

    const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(
      `${proto}://${window.location.host}/api/logs?service=${service}&token=${token}`
    )
    wsRef.current = ws

    ws.onmessage = (e) => term.writeln(e.data)
    ws.onerror = () => term.writeln('\r\n[connection error]')
    ws.onclose = (e) => {
      if (e.code === 4401) {
        term.writeln('\r\n[unauthorized — token invalid]')
      } else {
        term.writeln('\r\n[disconnected]')
      }
    }

    return () => {
      ws.close()
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
