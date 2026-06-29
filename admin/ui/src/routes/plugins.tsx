import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { Trash2, Upload } from 'lucide-react'

export const Route = createFileRoute('/plugins')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: PluginsPage,
})

interface Plugin {
  filename: string
  size: string
}

function PluginsPage() {
  const [plugins, setPlugins] = useState<Plugin[]>([])
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  async function load() {
    try {
      const d = await apiJson<{ plugins: Plugin[] }>('/api/plugins')
      setPlugins(d.plugins)
    } catch (e: any) {
      toast.error(e.message)
    }
  }

  useEffect(() => { load() }, [])

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    const form = new FormData()
    form.append('file', file)
    setUploading(true)
    try {
      const res = await apiFetch('/api/plugins', { method: 'POST', body: form })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      toast.success(`${file.name} uploaded`)
      load()
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      setUploading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  async function handleDelete(plugin: Plugin) {
    if (!confirm(`Delete plugin "${plugin.filename}"? This cannot be undone.`)) return
    try {
      const res = await apiFetch(`/api/plugins/${encodeURIComponent(plugin.filename)}`, { method: 'DELETE' })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      toast.success(`${plugin.filename} deleted`)
      load()
    } catch (e: any) {
      toast.error(e.message)
    }
  }

  return (
    <Layout>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-xl font-semibold">Plugins</h1>
          <button
            onClick={() => fileRef.current?.click()}
            disabled={uploading}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white text-sm rounded-md transition-colors"
          >
            <Upload size={14} />
            {uploading ? 'Uploading…' : 'Upload APK'}
          </button>
          <input
            ref={fileRef}
            type="file"
            accept=".apk,.zip"
            className="hidden"
            onChange={handleUpload}
          />
        </div>

        <div className="rounded-lg border border-zinc-800 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">File</th>
                <th className="px-4 py-3 text-left font-medium">Size</th>
                <th className="px-4 py-3 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {plugins.length === 0 && (
                <tr>
                  <td colSpan={3} className="px-4 py-8 text-center text-zinc-500">
                    No plugins uploaded
                  </td>
                </tr>
              )}
              {plugins.map(p => (
                <tr key={p.filename} className="bg-zinc-950 hover:bg-zinc-900/50">
                  <td className="px-4 py-3 font-mono">{p.filename}</td>
                  <td className="px-4 py-3 text-zinc-400">{p.size}</td>
                  <td className="px-4 py-3">
                    <div className="flex justify-end">
                      <button
                        onClick={() => handleDelete(p)}
                        className="p-1.5 rounded hover:bg-zinc-800 text-red-400"
                        title="Delete"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
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
