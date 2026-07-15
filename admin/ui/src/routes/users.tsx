import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { apiJson, apiFetch, downloadFile, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { notify } from '@/lib/notify'
import { TableSkeletonRows } from '@/components/Skeleton'
import { HudCorners } from '@/components/HudCorners'
import { PasswordInput } from '@/components/PasswordInput'
import { UserPlus, Trash2, CheckCircle, XCircle, KeyRound, Download, RefreshCw, Pencil } from 'lucide-react'

export const Route = createFileRoute('/users')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: UsersPage,
})

type Step = 'form' | 'gen-cert' | 'make-package' | 'enable' | 'done'

function CertBadge({ daysRemaining }: { daysRemaining: number | null }) {
  if (daysRemaining === null) return <span className="text-xs text-zinc-600">—</span>
  const cls = daysRemaining < 7
    ? 'text-red-600 dark:text-red-400 bg-red-100 dark:bg-red-400/10'
    : daysRemaining < 30
      ? 'text-yellow-600 dark:text-yellow-400 bg-yellow-100 dark:bg-yellow-400/10'
      : 'text-green-600 dark:text-green-400 bg-green-100 dark:bg-green-400/10'
  return <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${cls}`}>{daysRemaining}d</span>
}

function UserTable({ users, loading, emptyText, createFieldLogin, renameFieldAccount, downloadPackage, enableUser, disableUser, setSetPwUser, deleteUser, pendingUsers }: {
  users: TakUser[]
  loading: boolean
  emptyText: string
  createFieldLogin: (username: string) => void
  renameFieldAccount: (baseCallsign: string, currentName: string) => void
  downloadPackage: (username: string) => void
  enableUser: (username: string) => void
  disableUser: (username: string) => void
  setSetPwUser: (username: string) => void
  deleteUser: (username: string) => void
  pendingUsers: Set<string>
}) {
  return (
    <div className="hud-frame relative rounded-md border border-zinc-200 dark:border-white/10 bg-white dark:bg-[#0c0c0e] mb-6">
      <HudCorners />
      <div className="overflow-x-auto">
      <table className="w-full text-sm min-w-[560px]">
        <thead className="bg-zinc-100 dark:bg-[#141416] text-zinc-600 dark:text-zinc-400">
          <tr>
            <th className="px-4 py-3 text-left font-medium hud-label text-xs">Callsign</th>
            <th className="px-4 py-3 text-left font-medium hud-label text-xs">Web Login</th>
            <th className="px-4 py-3 text-left font-medium hud-label text-xs">Cert</th>
            <th className="px-4 py-3 text-right font-medium hud-label text-xs">Actions</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-200 dark:divide-white/10">
          {loading ? (
            <TableSkeletonRows columns={4} />
          ) : users.length === 0 ? (
            <tr className="bg-zinc-50 dark:bg-[#0c0c0e]"><td colSpan={4} className="px-4 py-8 text-center text-zinc-500">{emptyText}</td></tr>
          ) : (
            users.map(u => (
              <tr key={u.username} className="bg-zinc-50 dark:bg-[#000000] hover:bg-zinc-100/50 dark:hover:bg-white/[0.03]">
                <td className="px-4 py-3 font-mono">{u.username}</td>
                <td className="px-4 py-3">
                  {u.has_field_account
                    ? (
                      <span className="inline-flex items-center gap-1">
                        <span className="text-xs px-2 py-0.5 rounded-full font-medium text-green-600 dark:text-green-400 bg-green-100 dark:bg-green-400/10">active ({u.field_username})</span>
                        <button onClick={() => renameFieldAccount(u.base_callsign, u.field_username)} disabled={pendingUsers.has(u.base_callsign)} title="Rename login" aria-label="Rename login" className="p-1 rounded hover:bg-zinc-200 dark:hover:bg-[#141416] text-zinc-600 dark:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-accent-ring disabled:opacity-50"><Pencil size={12} /></button>
                      </span>
                    )
                    : <button onClick={() => createFieldLogin(u.username)} disabled={pendingUsers.has(u.username)} className="text-xs px-2 py-1 rounded bg-zinc-200 dark:bg-[#141416] hover:bg-zinc-300 dark:hover:bg-[#232326] text-zinc-700 dark:text-zinc-300 disabled:opacity-50">Create login</button>
                  }
                </td>
                <td className="px-4 py-3">
                  <CertBadge daysRemaining={u.cert_days_remaining} />
                </td>
                <td className="px-4 py-3 flex justify-end gap-2">
                  <button onClick={() => downloadPackage(u.username)} disabled={pendingUsers.has(u.username)} title="Download package" aria-label="Download package" className="p-1.5 rounded hover:bg-zinc-200 dark:hover:bg-[#141416] text-accent-ring focus:outline-none focus:ring-2 focus:ring-accent-ring disabled:opacity-50"><Download size={14} /></button>
                  <button onClick={() => enableUser(u.username)} disabled={pendingUsers.has(u.username)} title="Enable" aria-label="Enable" className="p-1.5 rounded hover:bg-zinc-200 dark:hover:bg-[#141416] text-green-600 dark:text-green-400 focus:outline-none focus:ring-2 focus:ring-accent-ring disabled:opacity-50"><CheckCircle size={14} /></button>
                  <button onClick={() => disableUser(u.username)} disabled={pendingUsers.has(u.username)} title="Disable" aria-label="Disable" className="p-1.5 rounded hover:bg-zinc-200 dark:hover:bg-[#141416] text-yellow-600 dark:text-yellow-400 focus:outline-none focus:ring-2 focus:ring-accent-ring disabled:opacity-50"><XCircle size={14} /></button>
                  <button onClick={() => setSetPwUser(u.username)} title="Set Password" aria-label="Set Password" className="p-1.5 rounded hover:bg-zinc-200 dark:hover:bg-[#141416] text-accent-ring focus:outline-none focus:ring-2 focus:ring-accent-ring"><KeyRound size={14} /></button>
                  <button onClick={() => deleteUser(u.username)} disabled={pendingUsers.has(u.username)} title="Delete" aria-label="Delete" className="p-1.5 rounded hover:bg-zinc-200 dark:hover:bg-[#141416] text-red-600 dark:text-red-400 focus:outline-none focus:ring-2 focus:ring-accent-ring disabled:opacity-50"><Trash2 size={14} /></button>
                </td>
              </tr>
            ))
          )}
        </tbody>
      </table>
      </div>
    </div>
  )
}

function NewUserModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [callsign, setCallsign] = useState('')
  const [clientType, setClientType] = useState<'ATAK' | 'WinTAK' | 'iTAK' | 'Service'>('iTAK')
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
      notify.error(errorMessage(e))
      setStep('form')
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-zinc-100 dark:bg-[#0c0c0e] border border-zinc-300 dark:border-white/10 rounded-md p-6 w-full max-w-md">
        <h2 className="text-lg font-semibold mb-4">New TAK User</h2>

        {step === 'form' && (
          <form onSubmit={handleCreate} className="space-y-4">
            <div className="space-y-1">
              <label className="text-sm text-zinc-700 dark:text-zinc-300">Callsign</label>
              <input type="text" value={callsign}
                onChange={e => setCallsign(e.target.value.replace(/[^a-zA-Z0-9_-]/g, ''))}
                placeholder="e.g. alpha1" required
                className="w-full px-3 py-2 rounded-md bg-zinc-200 dark:bg-[#141416] border border-zinc-300 dark:border-white/10 text-zinc-900 dark:text-white text-sm focus:outline-none focus:ring-2 focus:ring-accent-ring" />
              <p className="text-xs text-zinc-500">Letters, numbers, hyphens, underscores only.</p>
            </div>
            <div className="space-y-1">
              <label className="text-sm text-zinc-700 dark:text-zinc-300">Client</label>
              <select value={clientType} onChange={e => setClientType(e.target.value as 'ATAK' | 'WinTAK' | 'iTAK' | 'Service')}
                className="w-full px-3 py-2 rounded-md bg-zinc-200 dark:bg-[#141416] border border-zinc-300 dark:border-white/10 text-zinc-900 dark:text-white text-sm focus:outline-none focus:ring-2 focus:ring-accent-ring">
                <option value="iTAK">iTAK (iOS)</option>
                <option value="ATAK">ATAK (Android)</option>
                <option value="WinTAK">WinTAK (Windows)</option>
                <option value="Service">Service (no client app)</option>
              </select>
              <p className="text-xs text-zinc-500">iTAK uses a different package layout than ATAK/WinTAK — pick the right one. Service accounts are for automated/API integrations, not a TAK client app.</p>
            </div>
            {username && <p className="text-xs text-zinc-500">Package name: <span className="font-mono text-zinc-700 dark:text-zinc-300">{username}</span></p>}
            <div className="flex gap-2">
              <button type="button" onClick={onClose} className="flex-1 py-2 rounded bg-zinc-300 dark:bg-[#232326] hover:bg-zinc-400 dark:hover:bg-[#2b2b2f] text-sm">Cancel</button>
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
                <div key={s.id} className={`flex items-center gap-3 p-3 rounded-md border ${active ? 'border-accent-fill bg-accent-fill/10' : done ? 'border-zinc-300 dark:border-white/10 bg-zinc-100 dark:bg-[#0c0c0e]' : 'border-zinc-200 dark:border-white/10 opacity-40'}`}>
                  {done ? <CheckCircle size={16} className="text-green-600 dark:text-green-400 shrink-0" /> : <div className={`w-4 h-4 rounded-full border-2 shrink-0 ${active ? 'border-accent-ring animate-pulse' : 'border-zinc-400 dark:border-white/15'}`} />}
                  <span className="text-sm">{s.label}</span>
                </div>
              )
            })}
          </div>
        )}

        {step === 'done' && (
          <div className="space-y-4">
            <div className="flex items-center gap-2 text-green-600 dark:text-green-400">
              <CheckCircle size={18} />
              <span className="font-medium">{username} is ready</span>
            </div>
            {packageReady && (
              <button onClick={() => downloadFile(`/api/packages/${encodeURIComponent(username)}/download`, `${username}.zip`).catch((e) => notify.error(errorMessage(e)))}
                className="inline-block px-4 py-2 bg-zinc-200 dark:bg-[#141416] hover:bg-zinc-300 dark:hover:bg-[#232326] text-zinc-900 dark:text-white text-sm rounded-md transition-colors">
                Download data package
              </button>
            )}
            {fieldAccount && (
              <div className="p-3 rounded-md border border-yellow-300 dark:border-yellow-700/50 bg-yellow-50 dark:bg-yellow-900/20 text-sm space-y-1">
                <p className="text-yellow-800 dark:text-yellow-200">Field login created — shown once, save it now:</p>
                <p className="font-mono text-zinc-800 dark:text-zinc-200">user: {fieldAccount.username}</p>
                <p className="font-mono text-zinc-800 dark:text-zinc-200">pass: {fieldAccount.password}</p>
              </div>
            )}
            <button onClick={onClose}
              className="block px-4 py-2 bg-zinc-300 dark:bg-[#232326] hover:bg-zinc-400 dark:hover:bg-[#2b2b2f] text-zinc-900 dark:text-white text-sm rounded-md transition-colors">
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
    if (password !== confirm) { notify.error('Passwords do not match'); return }
    setLoading(true)
    try {
      await apiJson('/api/users/set-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      })
      notify.success(`Password set for ${username}`)
      onClose()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-zinc-100 dark:bg-[#0c0c0e] border border-zinc-300 dark:border-white/10 rounded-md p-6 w-full max-w-sm">
        <h2 className="text-lg font-semibold mb-1">Set Password</h2>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-4">TAK Server web UI password for <span className="font-mono text-zinc-800 dark:text-zinc-200">{username}</span></p>
        <form onSubmit={handleSubmit} className="space-y-3">
          <PasswordInput placeholder="New password (min 12 chars)" value={password}
            onChange={e => setPassword(e.target.value)}
            className="w-full bg-zinc-200 dark:bg-[#141416] border border-zinc-300 dark:border-white/10 rounded px-3 py-2 text-sm" required />
          <PasswordInput placeholder="Confirm password" value={confirm}
            onChange={e => setConfirm(e.target.value)}
            className="w-full bg-zinc-200 dark:bg-[#141416] border border-zinc-300 dark:border-white/10 rounded px-3 py-2 text-sm" required />
          <div className="flex gap-2 pt-1">
            <button type="button" onClick={onClose} className="flex-1 py-2 rounded bg-zinc-300 dark:bg-[#232326] hover:bg-zinc-400 dark:hover:bg-[#2b2b2f] text-sm">Cancel</button>
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
  const [loading, setLoading] = useState(true)
  const [showNew, setShowNew] = useState(false)
  const [setPwUser, setSetPwUser] = useState<string | null>(null)
  const [syncing, setSyncing] = useState(false)
  const [fieldResult, setFieldResult] = useState<{ username: string; password: string | null; created: boolean } | null>(null)
  const [syncedAccounts, setSyncedAccounts] = useState<{ username: string; password: string }[]>([])
  const [pendingUsers, setPendingUsers] = useState<Set<string>>(new Set())

  async function load() {
    try {
      const data = await apiJson<{ users: TakUser[] }>('/api/users')
      setUsers(data.users)
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function withPending(username: string, fn: () => Promise<void>) {
    if (pendingUsers.has(username)) return
    setPendingUsers(prev => new Set(prev).add(username))
    try {
      await fn()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setPendingUsers(prev => { const next = new Set(prev); next.delete(username); return next })
    }
  }

  async function createFieldLogin(username: string) {
    await withPending(username, async () => {
      const res = await apiJson<{ field_username: string; field_account_password: string | null; field_account_created: boolean }>(
        `/api/users/create-field-login/${encodeURIComponent(username)}`, { method: 'POST' }
      )
      setFieldResult({ username: res.field_username, password: res.field_account_password, created: res.field_account_created })
      load()
    })
  }

  async function renameFieldAccount(baseCallsign: string, currentName: string) {
    const newUsername = prompt(`Rename web login "${currentName}" to:`, currentName)
    if (!newUsername || newUsername === currentName) return
    await withPending(baseCallsign, async () => {
      await apiJson(`/api/users/field-account/${encodeURIComponent(baseCallsign)}/rename`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ new_username: newUsername }),
      })
      notify.success(`Renamed to ${newUsername}`)
      load()
    })
  }

  async function syncAccounts() {
    setSyncing(true)
    try {
      const res = await apiJson<{ created: { username: string; password: string }[] }>('/api/users/backfill-field-accounts', { method: 'POST' })
      setSyncedAccounts(res.created)
      if (res.created.length === 0) {
        notify.success('All packages already have field accounts')
      } else {
        notify.success(`Created ${res.created.length} field account(s) — shown below, save now`)
      }
      load()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setSyncing(false)
    }
  }

  async function enableUser(username: string) {
    await withPending(username, async () => {
      await apiJson('/api/users/enable', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      notify.success(`${username} enabled`)
    })
  }

  async function downloadPackage(username: string) {
    await withPending(username, async () => {
      await downloadFile(`/api/packages/${encodeURIComponent(username)}/download`, `${username}.zip`)
    })
  }

  async function disableUser(username: string) {
    await withPending(username, async () => {
      await apiJson('/api/users/disable', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username }) })
      notify.success(`${username} disabled`)
    })
  }

  async function deleteUser(username: string) {
    if (!confirm(`Delete ${username}? This cannot be undone.`)) return
    await withPending(username, async () => {
      const res = await apiFetch(`/api/users/${username}`, { method: 'DELETE' })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      notify.success(`${username} deleted`)
      load()
    })
  }

  return (
    <Layout>
      <div className="p-6">
        <PageHeader
          title="TAK Users"
          actions={
            <>
              <button onClick={syncAccounts} disabled={syncing}
                className="flex items-center gap-2 px-4 py-2 bg-zinc-300 dark:bg-[#232326] hover:bg-zinc-400 dark:hover:bg-[#2b2b2f] disabled:opacity-50 text-zinc-900 dark:text-white text-sm rounded-md transition-colors">
                <RefreshCw size={14} className={syncing ? 'animate-spin' : ''} /> {syncing ? 'Syncing…' : 'Sync Accounts'}
              </button>
              <button onClick={() => setShowNew(true)}
                className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm rounded-md transition-colors">
                <UserPlus size={14} /> New User
              </button>
            </>
          }
        />
        {(fieldResult || syncedAccounts.length > 0) && (
          <div className="mb-6 p-3 rounded-md border border-yellow-300 dark:border-yellow-700/50 bg-yellow-50 dark:bg-yellow-900/20 text-sm space-y-1">
            <p className="text-yellow-800 dark:text-yellow-200">Field login(s) created — shown once, save now:</p>
            {fieldResult?.created && <p className="font-mono text-zinc-800 dark:text-zinc-200">{fieldResult.username}: {fieldResult.password}</p>}
            {syncedAccounts.map(a => (
              <p key={a.username} className="font-mono text-zinc-800 dark:text-zinc-200">{a.username}: {a.password}</p>
            ))}
          </div>
        )}
        <h2 className="text-sm font-semibold text-zinc-600 dark:text-zinc-400 uppercase tracking-wider mb-3">TAK Users</h2>
        <UserTable
          users={users.filter(u => u.is_client)}
          loading={loading}
          emptyText="No users yet — create one"
          createFieldLogin={createFieldLogin}
          renameFieldAccount={renameFieldAccount}
          downloadPackage={downloadPackage}
          enableUser={enableUser}
          disableUser={disableUser}
          setSetPwUser={setSetPwUser}
          deleteUser={deleteUser}
          pendingUsers={pendingUsers}
        />

        <h2 className="text-sm font-semibold text-zinc-600 dark:text-zinc-400 uppercase tracking-wider mb-3 mt-8">Service Accounts</h2>
        <UserTable
          users={users.filter(u => !u.is_client)}
          loading={loading}
          emptyText="No service accounts — create one with make add-service"
          createFieldLogin={createFieldLogin}
          renameFieldAccount={renameFieldAccount}
          downloadPackage={downloadPackage}
          enableUser={enableUser}
          disableUser={disableUser}
          setSetPwUser={setSetPwUser}
          deleteUser={deleteUser}
          pendingUsers={pendingUsers}
        />
      </div>
      {showNew && <NewUserModal onClose={() => setShowNew(false)} onCreated={load} />}
      {setPwUser && <SetPasswordModal username={setPwUser} onClose={() => setSetPwUser(null)} />}
    </Layout>
  )
}
