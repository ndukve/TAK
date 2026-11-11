import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { apiJson, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { notify } from '@/lib/notify'

export const Route = createFileRoute('/groups')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: GroupsPage,
})

interface GroupEntry { name: string; members: string[] }
interface UserEntry { username: string; groups: string[] }
interface GroupsResponse { groups: GroupEntry[]; users: UserEntry[]; default_group: string }
type Mode = 'set' | 'add' | 'remove'

const inputClass = 'w-full rounded-md border border-zinc-200 bg-transparent px-3 py-2 text-sm dark:border-white/10'
const split = (text: string) => text.split(/[\s,]+/).filter(Boolean)

function GroupsPage() {
  const [data, setData] = useState<GroupsResponse | null>(null)
  const [username, setUsername] = useState('')
  const [mode, setMode] = useState<Mode>('add')
  const [both, setBoth] = useState('')
  const [send, setSend] = useState('')
  const [receive, setReceive] = useState('')
  const [busy, setBusy] = useState(false)

  async function load() {
    try { setData(await apiJson<GroupsResponse>('/api/groups')) } catch (error) { notify.error(errorMessage(error)) }
  }
  useEffect(() => { load() }, [])

  const isService = username.endsWith('-Service')
  const effectiveMode: Mode = isService ? 'add' : mode

  async function apply(event: React.FormEvent) {
    event.preventDefault()
    if (!window.confirm(`${effectiveMode === 'set' ? 'Replace the groups of' : effectiveMode === 'add' ? 'Add groups to' : 'Remove groups from'} ${username}?`)) return
    setBusy(true)
    try {
      await apiJson('/api/groups/assign', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, mode: effectiveMode, both: split(both), send: split(send), receive: split(receive) }),
      })
      notify.success(`Groups updated for ${username}`)
      setBoth(''); setSend(''); setReceive('')
      await load()
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Layout>
      <div className="p-6">
        <PageHeader title="Groups" count={data?.groups.length} countLabel="groups" />
        <p className="mb-4 max-w-3xl text-xs text-zinc-500">
          Groups are what ATAK shows as channels. A group exists once a user is put in it. New client packages are put in <b>{data?.default_group ?? 'TAK-USERS'}</b> with send and receive.
          Changes use TAK Server's own tool and take effect on the user's next connection (an already connected client may need to reconnect).
        </p>

        <div className="mb-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {(data?.groups ?? []).map(group => (
            <div key={group.name} className="rounded-lg border border-zinc-200 p-3 dark:border-white/10">
              <div className="flex items-center justify-between"><span className="font-medium">{group.name}</span><span className="text-xs text-zinc-500">{group.members.length} users</span></div>
              <p className="mt-1 break-words font-mono text-[11px] text-zinc-500">{group.members.join(', ')}</p>
            </div>
          ))}
        </div>

        <form onSubmit={apply} className="mb-6 rounded-lg border border-zinc-200 p-4 dark:border-white/10">
          <h2 className="mb-3 text-sm font-semibold">Change a user's groups</h2>
          <div className="grid gap-3 md:grid-cols-4">
            <label className="text-xs text-zinc-500">User (certificate name)
              <input list="tak-users" className={`${inputClass} mt-1 font-mono`} value={username} onChange={e => setUsername(e.target.value)} placeholder="alpha1-ATAK" required />
              <datalist id="tak-users">{(data?.users ?? []).filter(u => !u.groups.includes('revoked')).map(u => <option key={u.username} value={u.username} />)}</datalist>
            </label>
            <label className="text-xs text-zinc-500">What to do
              <select className={`${inputClass} mt-1`} value={effectiveMode} onChange={e => setMode(e.target.value as Mode)} disabled={isService}>
                <option value="add">Add to the groups they have</option>
                <option value="remove">Remove from groups</option>
                <option value="set">Replace all their groups</option>
              </select>
              {isService && <span className="text-[11px] text-amber-500">Service accounts (EFDI's feed): add only.</span>}
            </label>
            <label className="text-xs text-zinc-500 md:col-span-2">Send and receive (comma separated)
              <input className={`${inputClass} mt-1 font-mono`} value={both} onChange={e => setBoth(e.target.value)} placeholder="Alpha, Medics" />
            </label>
            <label className="text-xs text-zinc-500 md:col-span-2">Send only (the user writes to the group)
              <input className={`${inputClass} mt-1 font-mono`} value={send} onChange={e => setSend(e.target.value)} placeholder="" />
            </label>
            <label className="text-xs text-zinc-500 md:col-span-2">Receive only (the user reads the group)
              <input className={`${inputClass} mt-1 font-mono`} value={receive} onChange={e => setReceive(e.target.value)} placeholder="Logistics" />
            </label>
          </div>
          <button disabled={busy || !username || (!both && !send && !receive)} className="mt-3 rounded-md bg-[#004990] px-4 py-2 text-sm text-white disabled:opacity-40">{busy ? 'Applying…' : 'Apply'}</button>
        </form>

        <div className="overflow-hidden rounded-lg border border-zinc-200 dark:border-white/10">
          <table className="w-full min-w-[480px] text-sm">
            <thead className="text-zinc-500"><tr><th className="border-b border-zinc-200 px-4 py-2.5 text-left text-[10px] font-normal uppercase tracking-[0.1em] dark:border-white/10">User</th><th className="border-b border-zinc-200 px-4 py-2.5 text-left text-[10px] font-normal uppercase tracking-[0.1em] dark:border-white/10">Groups</th></tr></thead>
            <tbody>
              {(data?.users ?? []).map(user => (
                <tr key={user.username} className="cursor-pointer hover:bg-zinc-50 dark:hover:bg-white/5" onClick={() => setUsername(user.username)}>
                  <td className="border-b border-zinc-100 px-4 py-2 font-mono text-xs dark:border-white/5">{user.username}</td>
                  <td className="border-b border-zinc-100 px-4 py-2 text-xs dark:border-white/5">{user.groups.join(', ') || <span className="text-zinc-500">none</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  )
}
