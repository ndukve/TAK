import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { UserPlus, Trash2, CheckCircle, XCircle, KeyRound } from 'lucide-react'

export const Route = createFileRoute('/users')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: UsersPage,
})

type Step = 'form' | 'gen-cert' | 'make-package' | 'enable' | 'done'

function NewUserModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [callsign, setCallsign] = useState('')
  const [clientType, setClientType] = useState<'ATAK' | 'WinTAK' | 'iTAK'>('iTAK')
  const [step, setStep] = useState<Step>('form')
  const [downloadUrl, setDownloadUrl] = useState('')

  const username = callsign.trim() ? `${callsign}-${clientType}` : ''

  const steps: { id: Step; label: string }[] = [
    { id: 'gen-cert', label: 'Generate device certificate' },
    { id: 'make-package', label: 'Build data package' },
    { id: 'enable', label: 'Authorize on server' },
  ]
  const stepOrder: Step[] = ['form', 'gen-cert', 'make-package', 'enable', 'done']

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    if (!username.trim()) return
    try {
      setStep('gen-cert')
      await apiJson('/api/users/gen-cert', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      setStep('make-package')
      const pkg = await apiJson<any>('/api/users/make-package', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      if (pkg.download_url) setDownloadUrl(pkg.download_url)
      setStep('enable')
      await apiJson('/api/users/enable', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      setStep('done')
      onCreated()
    } catch (e: any) {
      toast.error(e.message)
      setStep('form')
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-zinc-900 border border-zinc-700 rounded-lg p-6 w-full max-w-md">
        <h2 className="text-lg font-semibold mb-4">New TAK User</h2>

        {step === 'form' && (
          <form onSubmit={handleCreate} className="space-y-4">
            <div className="space-y-1">
              <label className="text-sm text-zinc-300">Callsign</label>
              <input type="text" value={callsign}
                onChange={e => setCallsign(e.target.value.replace(/[^a-zA-Z0-9_-]/g, ''))}
                placeholder="e.g. alpha1" required
                className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              <p className="text-xs text-zinc-500">Letters, numbers, hyphens, underscores only.</p>
            </div>
            <div className="space-y-1">
              <label className="text-sm text-zinc-300">Client</label>
              <select value={clientType} onChange={e => setClientType(e.target.value as any)}
                className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
                <option value="iTAK">iTAK (iOS)</option>
                <option value="ATAK">ATAK (Android)</option>
                <option value="WinTAK">WinTAK (Windows)</option>
              </select>
              <p className="text-xs text-zinc-500">iTAK uses a different package layout than ATAK/WinTAK — pick the right one.</p>
            </div>
            {username && <p className="text-xs text-zinc-500">Package name: <span className="font-mono text-zinc-300">{username}</span></p>}
            <div className="flex gap-2">
              <button type="button" onClick={onClose} className="flex-1 py-2 rounded bg-zinc-700 hover:bg-zinc-600 text-sm">Cancel</button>
              <button type="submit" disabled={!username.trim()}
                className="flex-1 py-2 rounded bg-blue-600 hover:bg-blue-500 text-sm disabled:opacity-50">Create</button>
            </div>
          </form>
        )}

        {step !== 'form' && step !== 'done' && (
          <div className="space-y-3">
            {steps.map(s => {
              const idx = stepOrder.indexOf(s.id)
              const currentIdx = stepOrder.indexOf(step)
              const done = idx < currentIdx
              const active = s.id === step
              return (
                <div key={s.id} className={`flex items-center gap-3 p-3 rounded-lg border ${active ? 'border-blue-500 bg-blue-500/10' : done ? 'border-zinc-700 bg-zinc-900' : 'border-zinc-800 opacity-40'}`}>
                  {done ? <CheckCircle size={16} className="text-green-400 shrink-0" /> : <div className={`w-4 h-4 rounded-full border-2 shrink-0 ${active ? 'border-blue-400 animate-pulse' : 'border-zinc-600'}`} />}
                  <span className="text-sm">{s.label}</span>
                </div>
              )
            })}
          </div>
        )}

        {step === 'done' && (
          <div className="space-y-4">
            <div className="flex items-center gap-2 text-green-400">
              <CheckCircle size={18} />
              <span className="font-medium">{username} is ready</span>
            </div>
            {downloadUrl && (
              <a href={downloadUrl}
                className="inline-block px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-white text-sm rounded-md transition-colors">
                Download data package
              </a>
            )}
            <button onClick={onClose}
              className="block px-4 py-2 bg-zinc-700 hover:bg-zinc-600 text-white text-sm rounded-md transition-colors">
              Close
            </button>
          </div>
        )}
      </div>
    </div>
  )
}

function SetPasswordModal({ username, onClose }: { username: string; onClose: () => void }) {
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (password !== confirm) { toast.error('Passwords do not match'); return }
    setLoading(true)
    try {
      await apiJson('/api/users/set-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      })
      toast.success(`Password set for ${username}`)
      onClose()
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-zinc-900 border border-zinc-700 rounded-lg p-6 w-full max-w-sm">
        <h2 className="text-lg font-semibold mb-1">Set Password</h2>
        <p className="text-sm text-zinc-400 mb-4">TAK Server web UI password for <span className="font-mono text-zinc-200">{username}</span></p>
        <form onSubmit={handleSubmit} className="space-y-3">
          <input type="password" placeholder="New password (min 12 chars)" value={password}
            onChange={e => setPassword(e.target.value)}
            className="w-full bg-zinc-800 border border-zinc-700 rounded px-3 py-2 text-sm" required />
          <input type="password" placeholder="Confirm password" value={confirm}
            onChange={e => setConfirm(e.target.value)}
            className="w-full bg-zinc-800 border border-zinc-700 rounded px-3 py-2 text-sm" required />
          <div className="flex gap-2 pt-1">
            <button type="button" onClick={onClose} className="flex-1 py-2 rounded bg-zinc-700 hover:bg-zinc-600 text-sm">Cancel</button>
            <button type="submit" disabled={loading} className="flex-1 py-2 rounded bg-blue-600 hover:bg-blue-500 text-sm disabled:opacity-50">
              {loading ? 'Setting…' : 'Set Password'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function UsersPage() {
  const [users, setUsers] = useState<string[]>([])
  const [showNew, setShowNew] = useState(false)
  const [setPwUser, setSetPwUser] = useState<string | null>(null)

  async function load() {
    try {
      const data = await apiJson<{ users: string[] }>('/api/users')
      setUsers(data.users)
    } catch (e: any) {
      toast.error(e.message)
    }
  }

  useEffect(() => { load() }, [])

  async function enableUser(username: string) {
    try {
      await apiJson('/api/users/enable', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      toast.success(`${username} enabled`)
    } catch (e: any) { toast.error(e.message) }
  }

  async function disableUser(username: string) {
    try {
      await apiJson('/api/users/disable', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      toast.success(`${username} disabled`)
    } catch (e: any) { toast.error(e.message) }
  }

  async function deleteUser(username: string) {
    if (!confirm(`Delete ${username}? This cannot be undone.`)) return
    try {
      const res = await apiFetch(`/api/users/${username}`, { method: 'DELETE' })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      toast.success(`${username} deleted`)
      load()
    } catch (e: any) { toast.error(e.message) }
  }

  return (
    <Layout>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-xl font-semibold">TAK Users</h1>
          <button onClick={() => setShowNew(true)}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm rounded-md transition-colors">
            <UserPlus size={14} /> New User
          </button>
        </div>
        <div className="rounded-lg border border-zinc-800 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">Callsign</th>
                <th className="px-4 py-3 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {users.length === 0 && (
                <tr><td colSpan={2} className="px-4 py-8 text-center text-zinc-500">No users yet — create one</td></tr>
              )}
              {users.map(u => (
                <tr key={u} className="bg-zinc-950 hover:bg-zinc-900/50">
                  <td className="px-4 py-3 font-mono">{u}</td>
                  <td className="px-4 py-3 flex justify-end gap-2">
                    <button onClick={() => enableUser(u)} title="Enable" className="p-1.5 rounded hover:bg-zinc-800 text-green-400"><CheckCircle size={14} /></button>
                    <button onClick={() => disableUser(u)} title="Disable" className="p-1.5 rounded hover:bg-zinc-800 text-yellow-400"><XCircle size={14} /></button>
                    <button onClick={() => setSetPwUser(u)} title="Set Password" className="p-1.5 rounded hover:bg-zinc-800 text-blue-400"><KeyRound size={14} /></button>
                    <button onClick={() => deleteUser(u)} title="Delete" className="p-1.5 rounded hover:bg-zinc-800 text-red-400"><Trash2 size={14} /></button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      {showNew && <NewUserModal onClose={() => setShowNew(false)} onCreated={load} />}
      {setPwUser && <SetPasswordModal username={setPwUser} onClose={() => setSetPwUser(null)} />}
    </Layout>
  )
}
