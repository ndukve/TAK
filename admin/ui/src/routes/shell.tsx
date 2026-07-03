import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import { toast } from 'sonner'
import { ShieldAlert } from 'lucide-react'

export const Route = createFileRoute('/shell')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: ShellPage,
})

function ShellPage() {
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [ticket, setTicket] = useState<string | null>(null)
  const termRef = useRef<HTMLDivElement>(null)

  async function elevate(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const data = await apiJson<{ ticket: string }>('/auth/shell-elevate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      })
      setTicket(data.ticket)
      setPassword('')
    } catch (err: any) {
      toast.error(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (!ticket || !termRef.current) return

    const term = new Terminal({
      theme: { background: '#09090b' },
      cursorBlink: true,
      convertEol: true,
    })
    const fit = new FitAddon()
    term.loadAddon(fit)
    term.open(termRef.current)
    fit.fit()

    const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(`${proto}://${window.location.host}/api/shell/ws?t=${ticket}`)
    ws.binaryType = 'arraybuffer'

    ws.onopen = () => term.writeln('Connected to takserver_config\r\n')
    ws.onmessage = (e) => {
      if (e.data instanceof ArrayBuffer) term.write(new Uint8Array(e.data))
      else term.write(e.data)
    }
    ws.onclose = (e) => {
      if (e.code === 4001) {
        term.writeln('\r\n[session refused — invalid ticket]')
      } else {
        term.writeln('\r\n[session ended]')
      }
    }
    ws.onerror = () => term.writeln('\r\n[connection error]')

    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(data)
    })

    return () => {
      ws.close()
      term.dispose()
    }
  }, [ticket])

  return (
    <Layout>
      <div className="p-6 flex flex-col h-full">
        <h1 className="text-xl font-semibold mb-4">Shell — takserver_config</h1>

        {!ticket && (
          <div className="max-w-sm space-y-4">
            <div className="flex items-start gap-3 p-4 rounded-lg border border-yellow-700/50 bg-yellow-900/20">
              <ShieldAlert size={16} className="text-yellow-400 shrink-0 mt-0.5" />
              <p className="text-sm text-yellow-200">
                Re-enter your password to unlock shell access. Session expires in 5 minutes.
              </p>
            </div>
            <form onSubmit={elevate} className="space-y-3">
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Your admin password"
                required
                className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-accent-ring"
              />
              <button
                type="submit"
                disabled={loading}
                className="w-full py-2 rounded-md bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm font-medium disabled:opacity-50 transition-colors"
              >
                {loading ? 'Verifying…' : 'Unlock shell'}
              </button>
            </form>
          </div>
        )}

        {ticket && (
          <div
            ref={termRef}
            className="flex-1 rounded-lg overflow-hidden border border-zinc-800"
            style={{ minHeight: '500px' }}
          />
        )}
      </div>
    </Layout>
  )
}
