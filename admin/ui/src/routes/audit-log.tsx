import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'

export const Route = createFileRoute('/audit-log')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: AuditLogPage,
})

interface AuditEntry {
  id: string
  username: string
  action: string
  detail: string | null
  timestamp: string
}

function AuditLogPage() {
  const [entries, setEntries] = useState<AuditEntry[]>([])

  async function load() {
    try {
      const data = await apiJson<{ entries: AuditEntry[] }>('/api/audit-log')
      setEntries(data.entries)
    } catch (e: any) {
      toast.error(e.message)
    }
  }

  useEffect(() => { load() }, [])

  return (
    <Layout>
      <div className="p-6">
        <h1 className="text-xl font-semibold mb-6">Audit Log</h1>
        <div className="rounded-lg border border-zinc-800 overflow-x-auto">
          <table className="w-full text-sm min-w-[640px]">
            <thead className="bg-zinc-900 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">Time</th>
                <th className="px-4 py-3 text-left font-medium">User</th>
                <th className="px-4 py-3 text-left font-medium">Action</th>
                <th className="px-4 py-3 text-left font-medium">Detail</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {entries.length === 0 && (
                <tr><td colSpan={4} className="px-4 py-8 text-center text-zinc-500">No activity recorded yet</td></tr>
              )}
              {entries.map(e => (
                <tr key={e.id} className="bg-zinc-950 hover:bg-zinc-900/50">
                  <td className="px-4 py-3 text-zinc-400 whitespace-nowrap">{new Date(e.timestamp).toLocaleString()}</td>
                  <td className="px-4 py-3 font-mono">{e.username}</td>
                  <td className="px-4 py-3 text-zinc-300">{e.action}</td>
                  <td className="px-4 py-3 text-zinc-500 font-mono">{e.detail ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  )
}
