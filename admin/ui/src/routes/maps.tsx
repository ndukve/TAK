import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { Trash2, Upload } from 'lucide-react'

export const Route = createFileRoute('/maps')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: MapsPage,
})

interface MapSource {
  provider: string
  filename: string
  size: string
}

function MapsPage() {
  const [maps, setMaps] = useState<MapSource[]>([])
  const [uploading, setUploading] = useState(false)
  const [provider, setProvider] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  async function load() {
    try {
      const d = await apiJson<{ maps: MapSource[] }>('/api/maps')
      setMaps(d.maps)
    } catch (e: any) {
      toast.error(e.message)
    }
  }

  useEffect(() => { load() }, [])

  function handleUploadClick() {
    if (!provider.trim()) {
      toast.error('Enter a provider name before uploading')
      return
    }
    fileRef.current?.click()
  }

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    const form = new FormData()
    form.append('file', file)
    setUploading(true)
    try {
      const res = await apiFetch(`/api/maps?provider=${encodeURIComponent(provider.trim())}`, { method: 'POST', body: form })
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

  async function handleDelete(m: MapSource) {
    if (!confirm(`Delete "${m.provider}/${m.filename}"? This cannot be undone.`)) return
    try {
      const res = await apiFetch(`/api/maps/${encodeURIComponent(m.provider)}/${encodeURIComponent(m.filename)}`, { method: 'DELETE' })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      toast.success(`${m.filename} deleted`)
      load()
    } catch (e: any) {
      toast.error(e.message)
    }
  }

  return (
    <Layout>
      <div className="p-6">
        <div className="flex items-center gap-3 mb-6">
          <h1 className="text-xl font-semibold flex-1">Map Sources</h1>
          <input
            type="text"
            placeholder="Provider (e.g. Google)"
            value={provider}
            onChange={e => setProvider(e.target.value)}
            className="px-3 py-2 bg-zinc-900 border border-zinc-700 rounded-md text-sm text-white placeholder-zinc-500 w-48"
          />
          <button
            onClick={handleUploadClick}
            disabled={uploading}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white text-sm rounded-md transition-colors"
          >
            <Upload size={14} />
            {uploading ? 'Uploading…' : 'Upload XML'}
          </button>
          <input
            ref={fileRef}
            type="file"
            accept=".xml"
            className="hidden"
            onChange={handleUpload}
          />
        </div>

        <div className="rounded-lg border border-zinc-800 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">Provider</th>
                <th className="px-4 py-3 text-left font-medium">File</th>
                <th className="px-4 py-3 text-left font-medium">Size</th>
                <th className="px-4 py-3 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {maps.length === 0 && (
                <tr>
                  <td colSpan={4} className="px-4 py-8 text-center text-zinc-500">
                    No map sources loaded
                  </td>
                </tr>
              )}
              {maps.map(m => (
                <tr key={`${m.provider}/${m.filename}`} className="bg-zinc-950 hover:bg-zinc-900/50">
                  <td className="px-4 py-3 text-zinc-400">{m.provider}</td>
                  <td className="px-4 py-3 font-mono">{m.filename}</td>
                  <td className="px-4 py-3 text-zinc-400">{m.size}</td>
                  <td className="px-4 py-3">
                    <div className="flex justify-end">
                      <button
                        onClick={() => handleDelete(m)}
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
