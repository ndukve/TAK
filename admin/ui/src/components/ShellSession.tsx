import { useEffect, useRef, useState } from 'react'
import { Icon } from '@/components/ui/icon'
import { useAuth } from '@/store/auth'
import { useRoute } from '@/store/route'
import { apiJson, errorMessage } from '@/lib/api'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import { notify } from '@/lib/notify'
import { cn } from '@/lib/utils'
import { PasswordInput } from '@/components/PasswordInput'

// Mounted once at the app root (see main.tsx), never unmounted by routing —
// this is what makes the shell survive navigating away and back. shell.tsx's
// route only owns the auth guard; all state (ticket, xterm instance, the
// WebSocket) lives here so leaving the page hides this via CSS instead of
// tearing down the underlying docker exec session and its scrollback.
// Reads the current path from a plain store (published by Layout.tsx, which
// safely has router context) instead of touching the router directly — this
// component is rendered outside the router tree entirely.
export function ShellSession() {
  const { token, role, authProvider } = useAuth()
  const pathname = useRoute((s) => s.pathname)
  const onShellPage = pathname === '/shell'

  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [ticket, setTicket] = useState<string | null>(null)
  const termRef = useRef<HTMLDivElement>(null)
  const fitRef = useRef<FitAddon | null>(null)

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
    } catch (err) {
      notify.error(errorMessage(err))
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
    fitRef.current = fit
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
      // Drop back to the password form instead of leaving a dead terminal —
      // reconnecting means re-authenticating, same as being logged out.
      setTicket(null)
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

  // Logout, role changes, and a switch to an SSO session must tear down an
  // already-open terminal immediately rather than leaving the Docker exec
  // alive behind a hidden route.
  useEffect(() => {
    if (!token || role !== 'superadmin' || authProvider !== 'local') setTicket(null)
  }, [token, role, authProvider])

  // Re-fit whenever the shell page becomes visible again (its container may
  // have been display:none, where fitAddon can't measure it, since the last resize).
  useEffect(() => {
    if (onShellPage) fitRef.current?.fit()
  }, [onShellPage])

  if (!token || role !== 'superadmin' || authProvider !== 'local') return null

  return (
    <div
      className={cn(
        'fixed inset-y-0 right-0 z-10 top-14 md:top-0 md:left-56 left-0 bg-zinc-50 dark:bg-[#000000] p-6 flex flex-col',
        onShellPage ? 'block' : 'hidden'
      )}
    >
      <h1 className="text-xl font-semibold mb-4">Shell — takserver_config</h1>

      {!ticket && (
        <div className="max-w-sm space-y-4">
          <div className="flex items-start gap-3 p-4 rounded-none border border-yellow-300 dark:border-yellow-700/50 bg-yellow-50 dark:bg-yellow-900/20">
            <Icon name="shield-flash-line" size={16} className="text-yellow-600 dark:text-yellow-400 shrink-0 mt-0.5" />
            <p className="text-sm text-yellow-800 dark:text-yellow-200">
              Re-enter your password to unlock shell access. Session expires in 5 minutes.
            </p>
          </div>
          <form onSubmit={elevate} className="space-y-3">
            <PasswordInput
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Your admin password"
              required
              className="w-full px-3 py-2 rounded-none bg-zinc-200 dark:bg-[#141416] border border-zinc-300 dark:border-white/10 text-zinc-900 dark:text-white text-sm focus:outline-none focus:ring-2 focus:ring-accent-ring"
            />
            <button
              type="submit"
              disabled={loading}
              className="w-full py-2 rounded-none bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm font-medium disabled:opacity-50 transition-colors"
            >
              {loading ? 'Verifying…' : 'Unlock shell'}
            </button>
          </form>
        </div>
      )}

      {ticket && (
        <div
          ref={termRef}
          className="flex-1 rounded-none overflow-hidden border border-zinc-200 dark:border-white/10"
          style={{ minHeight: '500px' }}
        />
      )}
    </div>
  )
}
