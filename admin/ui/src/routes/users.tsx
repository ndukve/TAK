import { createFileRoute, redirect, Link } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { UserPlus, Trash2, CheckCircle, XCircle } from 'lucide-react'

export const Route = createFileRoute('/users')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: UsersPage,
})

function UsersPage() {
  const [users, setUsers] = useState<string[]>([])

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
      await apiJson('/api/users/enable', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username }),
      })
      toast.success(`${username} enabled`)
    } catch (e: any) { toast.error(e.message) }
  }

  async function disableUser(username: string) {
    try {
      await apiJson('/api/users/disable', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username }),
      })
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
          <Link to="/users/new" className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm rounded-md transition-colors">
            <UserPlus size={14} /> New User
          </Link>
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
                    <button onClick={() => deleteUser(u)} title="Delete" className="p-1.5 rounded hover:bg-zinc-800 text-red-400"><Trash2 size={14} /></button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  )
}
