import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { apiJson, apiFetch, downloadFile, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { notify } from '@/lib/notify'
import { TableSkeletonRows } from '@/components/Skeleton'
import { Trash2, Upload, Copy, Check, Download } from 'lucide-react'

function CopyHash({ hash }: { hash: string }) {
  const [copied, setCopied] = useState(false)
  function copy() {
    navigator.clipboard.writeText(hash)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }
  return (
    <button onClick={copy} title="Copy SHA-256" aria-label="Copy full SHA-256 hash" className="flex items-center gap-1 font-mono text-xs text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300 transition-colors focus:outline-none focus:ring-2 focus:ring-accent-ring">
      <span>{hash.slice(0, 16)}…</span>
      {copied ? <Check size={11} className="text-green-600 dark:text-green-400" /> : <Copy size={11} />}
    </button>
  )
}

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
  kind: 'xml' | 'mbtiles'
  size: string
  sha256: string | null
}

function MapsPage() {
  const [maps, setMaps] = useState<MapSource[]>([])
  const [loading, setLoading] = useState(true)
  const [uploading, setUploading] = useState(false)
  const [provider, setProvider] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  async function load() {
    try {
      const d = await apiJson<{ maps: MapSource[] }>('/api/maps')
      setMaps(d.maps)
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  function handleUploadClick() {
    if (!provider.trim()) {
      notify.error('Enter a provider name before uploading')
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
      notify.success(`${file.name} uploaded`)
      load()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setUploading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  async function handleDownload(m: MapSource) {
    try {
      await downloadFile(`/api/maps/${encodeURIComponent(m.provider)}/${encodeURIComponent(m.filename)}/download`, m.filename)
    } catch (e) {
      notify.error(errorMessage(e))
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
      notify.success(`${m.filename} deleted`)
      load()
    } catch (e) {
      notify.error(errorMessage(e))
    }
  }

  return (
    <Layout>
      <div className="p-6">
        <PageHeader title="Map Sources" />
        <div className="flex items-center gap-3 mb-6">
          <input
            type="text"
            placeholder="Provider (e.g. Google)"
            value={provider}
            onChange={e => setProvider(e.target.value)}
            className="px-3 py-2 bg-zinc-100 dark:bg-[#111113] border border-zinc-300 dark:border-white/10 rounded-md text-sm text-zinc-900 dark:text-white placeholder-zinc-500 w-48"
          />
          <button
            onClick={handleUploadClick}
            disabled={uploading}
            className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover disabled:opacity-50 text-accent-text text-sm rounded-md transition-colors"
          >
            <Upload size={14} />
            {uploading ? 'Uploading…' : 'Upload Map'}
          </button>
          <input
            ref={fileRef}
            type="file"
            accept=".xml,.mbtiles"
            className="hidden"
            onChange={handleUpload}
          />
        </div>

        <div className="rounded-md border border-zinc-200 dark:border-white/10 overflow-x-auto">
          <table className="w-full text-sm min-w-[600px]">
            <thead className="bg-zinc-100 dark:bg-[#111113] text-zinc-600 dark:text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium hud-label text-xs">Provider</th>
                <th className="px-4 py-3 text-left font-medium hud-label text-xs">File</th>
                <th className="px-4 py-3 text-left font-medium hud-label text-xs">Kind</th>
                <th className="px-4 py-3 text-left font-medium hud-label text-xs">Size</th>
                <th className="px-4 py-3 text-left font-medium hud-label text-xs">SHA-256</th>
                <th className="px-4 py-3 text-right font-medium hud-label text-xs">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-200 dark:divide-white/10">
              {loading ? (
                <TableSkeletonRows columns={6} />
              ) : maps.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-8 text-center text-zinc-500">
                    No map sources loaded
                  </td>
                </tr>
              ) : (
                maps.map(m => (
                  <tr key={`${m.provider}/${m.filename}`} className="bg-zinc-50 dark:bg-[#000000] hover:bg-zinc-100/50 dark:hover:bg-white/[0.03]">
                    <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">{m.provider}</td>
                    <td className="px-4 py-3 font-mono">{m.filename}</td>
                    <td className="px-4 py-3">
                      <span className={`px-1.5 py-0.5 rounded text-xs font-mono ${m.kind === 'mbtiles' ? 'bg-accent-fill/20 text-accent-ring' : 'bg-zinc-200 dark:bg-white/10 text-zinc-600 dark:text-zinc-400'}`}>
                        {m.kind === 'mbtiles' ? 'offline' : 'xml'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">{m.size}</td>
                    <td className="px-4 py-3">{m.sha256 ? <CopyHash hash={m.sha256} /> : <span className="text-zinc-400 dark:text-zinc-600 text-xs">—</span>}</td>
                    <td className="px-4 py-3">
                      <div className="flex justify-end gap-1">
                        <button
                          onClick={() => handleDownload(m)}
                          className="p-1.5 rounded hover:bg-zinc-200 dark:hover:bg-[#1a1a1d] text-accent-ring"
                          title="Download"
                        >
                          <Download size={14} />
                        </button>
                        <button
                          onClick={() => handleDelete(m)}
                          className="p-1.5 rounded hover:bg-zinc-200 dark:hover:bg-[#1a1a1d] text-red-600 dark:text-red-400"
                          title="Delete"
                        >
                          <Trash2 size={14} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  )
}
