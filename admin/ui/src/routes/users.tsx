import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch, downloadFile, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { UserPlus, Trash2, CheckCircle, XCircle, KeyRound, Download, RefreshCw, Pencil } from 'lucide-react'

export const Route = createFileRoute('/users')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role === 'field') throw redirect({ to: '/packages' })
  },
  component: UsersPage,
})

type Step = 'form' | 'gen-cert' | 'make-package' | 'enable' | 'done'

function CertBadge({ daysRemaining }: { daysRemaining: number | null }) {
  if (daysRemaining === null) return <span className="text-xs text-zinc-600">—</span>
  const cls = daysRemaining < 7
    ? 'text-red-400 bg-red-400/10'
    : daysRemaining < 30
      ? 'text-yellow-400 bg-yellow-400/10'
      : 'text-green-400 bg-green-400/10'
  return <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${cls}`}>{daysRemaining}d</span>
}

function UserTable({ users, emptyText, createFieldLogin, renameFieldAccount, downloadPackage, enableUser, disableUser, setSetPwUser, deleteUser }: {
  users: TakUser[]
  emptyText: string
  createFieldLogin: (username: string) => void
  renameFieldAccount: (baseCallsign: string, currentName: string) => void
  downloadPackage: (username: string) => void
  enableUser: (username: string) => void
  disableUser: (username: string) => void
  setSetPwUser: (username: string) => void
  deleteUser: (username: string) => void
}) {
  return (
    <div className="rounded-lg border border-zinc-800 overflow-x-auto mb-6">
      <table className="w-full text-sm min-w-[560px]">
        <thead className="bg-zinc-900 text-zinc-400">
          <tr>
            <th className="px-4 py-3 text-left font-medium">Callsign</th>
            <th className="px-4 py-3 text-left font-medium">Web Login</th>
            <th className="px-4 py-3 text-left font-medium">Cert</th>
            <th className="px-4 py-3 text-right font-medium">Actions</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-800">
          {users.length === 0 && (
            <tr><td colSpan={4} className="px-4 py-8 text-center text-zinc-500">{emptyText}</td></tr>
          )}
          {users.map(u => (
            <tr key={u.username} className="bg-zinc-950 hover:bg-zinc-900/50">
              <td className="px-4 py-3 font-mono">{u.username}</td>
              <td className="px-4 py-3">
                {u.has_field_account
                  ? (
                    <span className="inline-flex items-center gap-1">
                      <span className="text-xs px-2 py-0.5 rounded-full font-medium text-green-400 bg-green-400/10">active ({u.field_username})</span>
                      <button onClick={() => renameFieldAccount(u.base_callsign, u.field_username)} title="Rename login" className="p-1 rounded hover:bg-zinc-800 text-zinc-400"><Pencil size={12} /></button>
                    </span>
                  )
                  : <button onClick={() => createFieldLogin(u.username)} className="text-xs px-2 py-1 rounded bg-zinc-800 hover:bg-zinc-700 text-zinc-300">Create login</button>
                }
              </td>
              <td className="px-4 py-3">
                <CertBadge daysRemaining={u.cert_days_remaining} />
              </td>
              <td className="px-4 py-3 flex justify-end gap-2">
                <button onClick={() => downloadPackage(u.username)} title="Download package" className="p-1.5 rounded hover:bg-zinc-800 text-accent-ring"><Download size={14} /></button>
                <button onClick={() => enableUser(u.username)} title="Enable" className="p-1.5 rounded hover:bg-zinc-800 text-green-400"><CheckCircle size={14} /></button>
                <button onClick={() => disableUser(u.username)} title="Disable" className="p-1.5 rounded hover:bg-zinc-800 text-yellow-400"><XCircle size={14} /></button>
                <button onClick={() => setSetPwUser(u.username)} title="Set Password" className="p-1.5 rounded hover:bg-zinc-800 text-accent-ring"><KeyRound size={14} /></button>
                <button onClick={() => deleteUser(u.username)} title="Delete" className="p-1.5 rounded hover:bg-zinc-800 text-red-400"><Trash2 size={14} /></button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function NewUserModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [callsign, setCallsign] = useState('')
  const [clientType, setClientType] = useState<'ATAK' | 'WinTAK' | 'iTAK'>('iTAK')
  const [step, setStep] = useState<Step>('form')
  const [packageReady, setPackageReady] = useState(false)
  const [fieldAccount, setFieldAccount] = useState<{ username: string; password: string } | null>(null)

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
      const pkg = await apiJson<{ field_account_created: boolean; field_username: string; field_account_password: string | null }>(
        '/api/users/make-package', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) }
      )
      setPackageReady(true)
      if (pkg.field_account_created) {
        setFieldAccount({ username: pkg.field_username, password: pkg.field_account_password })
      }
      setStep('enable')
      await apiJson('/api/users/enable', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      setStep('done')
      onCreated()
    } catch (e) {
      toast.error(errorMessage(e))
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
                className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-accent-ring" />
              <p className="text-xs text-zinc-500">Letters, numbers, hyphens, underscores only.</p>
            </div>
            <div className="space-y-1">
              <label className="text-sm text-zinc-300">Client</label>
              <select value={clientType} onChange={e => setClientType(e.target.value as 'ATAK' | 'WinTAK' | 'iTAK')}
                className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-accent-ring">
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
                className="flex-1 py-2 rounded bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm disabled:opacity-50">Create</button>
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
                <div key={s.id} className={`flex items-center gap-3 p-3 rounded-lg border ${active ? 'border-accent-fill bg-accent-fill/10' : done ? 'border-zinc-700 bg-zinc-900' : 'border-zinc-800 opacity-40'}`}>
                  {done ? <CheckCircle size={16} className="text-green-400 shrink-0" /> : <div className={`w-4 h-4 rounded-full border-2 shrink-0 ${active ? 'border-accent-ring animate-pulse' : 'border-zinc-600'}`} />}
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
            {packageReady && (
              <button onClick={() => downloadFile(`/api/packages/${encodeURIComponent(username)}/download`, `${username}.zip`).catch((e) => toast.error(errorMessage(e)))}
                className="inline-block px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-white text-sm rounded-md transition-colors">
                Download data package
              </button>
            )}
            {fieldAccount && (
              <div className="p-3 rounded-lg border border-yellow-700/50 bg-yellow-900/20 text-sm space-y-1">
                <p className="text-yellow-200">Field login created — shown once, save it now:</p>
                <p className="font-mono text-zinc-200">user: {fieldAccount.username}</p>
                <p className="font-mono text-zinc-200">pass: {fieldAccount.password}</p>
              </div>
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
    } catch (e) {
      toast.error(errorMessage(e))
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
            <button type="submit" disabled={loading} className="flex-1 py-2 rounded bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm disabled:opacity-50">
              {loading ? 'Setting…' : 'Set Password'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

interface TakUser {
  username: string
  has_field_account: boolean
  field_username: string
  base_callsign: string
  cert_days_remaining: number | null
  is_client: boolean
}

function UsersPage() {
  const [users, setUsers] = useState<TakUser[]>([])
  const [showNew, setShowNew] = useState(false)
  const [setPwUser, setSetPwUser] = useState<string | null>(null)
  const [syncing, setSyncing] = useState(false)
  const [fieldResult, setFieldResult] = useState<{ username: string; password: string | null; created: boolean } | null>(null)
  const [syncedAccounts, setSyncedAccounts] = useState<{ username: string; password: string }[]>([])

  async function load() {
    try {
      const data = await apiJson<{ users: TakUser[] }>('/api/users')
      setUsers(data.users)
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  useEffect(() => { load() }, [])

  async function createFieldLogin(username: string) {
    try {
      const res = await apiJson<{ field_username: string; field_account_password: string | null; field_account_created: boolean }>(
        `/api/users/create-field-login/${encodeURIComponent(username)}`, { method: 'POST' }
      )
      setFieldResult({ username: res.field_username, password: res.field_account_password, created: res.field_account_created })
      load()
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  async function renameFieldAccount(baseCallsign: string, currentName: string) {
    const newUsername = prompt(`Rename web login "${currentName}" to:`, currentName)
    if (!newUsername || newUsername === currentName) return
    try {
      await apiJson(`/api/users/field-account/${encodeURIComponent(baseCallsign)}/rename`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ new_username: newUsername }),
      })
      toast.success(`Renamed to ${newUsername}`)
      load()
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  async function syncAccounts() {
    setSyncing(true)
    try {
      const res = await apiJson<{ created: { username: string; password: string }[] }>('/api/users/backfill-field-accounts', { method: 'POST' })
      setSyncedAccounts(res.created)
      if (res.created.length === 0) {
        toast.success('All packages already have field accounts')
      } else {
        toast.success(`Created ${res.created.length} field account(s) — shown below, save now`)
      }
      load()
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setSyncing(false)
    }
  }

  async function enableUser(username: string) {
    try {
      await apiJson('/api/users/enable', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      toast.success(`${username} enabled`)
    } catch (e) { toast.error(errorMessage(e)) }
  }

  async function downloadPackage(username: string) {
    try {
      await downloadFile(`/api/packages/${encodeURIComponent(username)}/download`, `${username}.zip`)
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  async function disableUser(username: string) {
    try {
      await apiJson('/api/users/disable', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      toast.success(`${username} disabled`)
    } catch (e) { toast.error(errorMessage(e)) }
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
    } catch (e) { toast.error(errorMessage(e)) }
  }

  return (
    <Layout>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-xl font-semibold">TAK Users</h1>
          <div className="flex items-center gap-2">
            <button onClick={syncAccounts} disabled={syncing}
              className="flex items-center gap-2 px-4 py-2 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 text-white text-sm rounded-md transition-colors">
              <RefreshCw size={14} className={syncing ? 'animate-spin' : ''} /> {syncing ? 'Syncing…' : 'Sync Accounts'}
            </button>
            <button onClick={() => setShowNew(true)}
              className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm rounded-md transition-colors">
              <UserPlus size={14} /> New User
            </button>
          </div>
        </div>
        {(fieldResult || syncedAccounts.length > 0) && (
          <div className="mb-6 p-3 rounded-lg border border-yellow-700/50 bg-yellow-900/20 text-sm space-y-1">
            <p className="text-yellow-200">Field login(s) created — shown once, save now:</p>
            {fieldResult?.created && <p className="font-mono text-zinc-200">{fieldResult.username}: {fieldResult.password}</p>}
            {syncedAccounts.map(a => (
              <p key={a.username} className="font-mono text-zinc-200">{a.username}: {a.password}</p>
            ))}
          </div>
        )}
        <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-3">TAK Users</h2>
        <UserTable
          users={users.filter(u => u.is_client)}
          emptyText="No users yet — create one"
          createFieldLogin={createFieldLogin}
          renameFieldAccount={renameFieldAccount}
          downloadPackage={downloadPackage}
          enableUser={enableUser}
          disableUser={disableUser}
          setSetPwUser={setSetPwUser}
          deleteUser={deleteUser}
        />

        <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-3 mt-8">Service Accounts</h2>
        <UserTable
          users={users.filter(u => !u.is_client)}
          emptyText="No service accounts — create one with make add-service"
          createFieldLogin={createFieldLogin}
          renameFieldAccount={renameFieldAccount}
          downloadPackage={downloadPackage}
          enableUser={enableUser}
          disableUser={disableUser}
          setSetPwUser={setSetPwUser}
          deleteUser={deleteUser}
        />
      </div>
      {showNew && <NewUserModal onClose={() => setShowNew(false)} onCreated={load} />}
      {setPwUser && <SetPasswordModal username={setPwUser} onClose={() => setSetPwUser(null)} />}
    </Layout>
  )
}
