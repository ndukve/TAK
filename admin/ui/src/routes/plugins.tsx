import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { apiFetch, apiJson, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { notify } from '@/lib/notify'
import { TableSkeletonRows } from '@/components/Skeleton'
import { HudCorners } from '@/components/HudCorners'
import { Trash2, Upload, Copy, Check } from 'lucide-react'

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
  sha256: string | null
}

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

function UploadModal({ onClose, onUploaded }: { onClose: () => void; onUploaded: () => void }) {
  const [file, setFile] = useState<File | null>(null)
  const [expectedHash, setExpectedHash] = useState('')
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!file) return
    const form = new FormData()
    form.append('file', file)
    if (expectedHash.trim()) form.append('expected_sha256', expectedHash.trim().toLowerCase())
    setUploading(true)
    try {
      const res = await apiFetch('/api/plugins', { method: 'POST', body: form })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      const data = await res.json()
      notify.success(`${file.name} uploaded — SHA-256: ${data.sha256?.slice(0, 16)}…`)
      onUploaded()
      onClose()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-zinc-100 dark:bg-[#0c0c0e] border border-zinc-300 dark:border-white/10 rounded-none p-6 w-full max-w-md">
        <h2 className="text-lg font-semibold mb-4">Upload Plugin</h2>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <input ref={fileRef} type="file" accept=".apk,.zip" className="hidden"
              onChange={e => setFile(e.target.files?.[0] ?? null)} />
            <button type="button" onClick={() => fileRef.current?.click()}
              className="w-full py-8 border-2 border-dashed border-zinc-300 dark:border-white/10 rounded-none text-zinc-600 dark:text-zinc-400 hover:border-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200 transition-colors text-sm">
              {file ? file.name : 'Click to select .apk or .zip'}
            </button>
          </div>
          <div className="space-y-1">
            <label className="text-xs text-zinc-600 dark:text-zinc-400">Expected SHA-256 (optional — from tak.gov)</label>
            <input type="text" value={expectedHash} onChange={e => setExpectedHash(e.target.value)}
              placeholder="e.g. a3f2c1…"
              className="w-full bg-zinc-200 dark:bg-[#141416] border border-zinc-300 dark:border-white/10 rounded-none px-3 py-2 text-xs font-mono" />
            <p className="text-xs text-zinc-500">If provided, upload is rejected if hash doesn't match.</p>
          </div>
          <div className="flex gap-2">
            <button type="button" onClick={onClose} className="flex-1 py-2 rounded-none bg-zinc-300 dark:bg-[#232326] hover:bg-zinc-400 dark:hover:bg-[#2b2b2f] text-sm">Cancel</button>
            <button type="submit" disabled={!file || uploading}
              className="flex-1 py-2 rounded-none bg-accent-fill hover:bg-accent-fill-hover text-accent-text disabled:opacity-50 text-sm">
              {uploading ? 'Uploading…' : 'Upload'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function PluginsPage() {
  const { role } = useAuth()
  const canManage = role !== 'field'
  const [plugins, setPlugins] = useState<Plugin[]>([])
  const [loading, setLoading] = useState(true)
  const [showUpload, setShowUpload] = useState(false)

  async function load() {
    try {
      const d = await apiJson<{ plugins: Plugin[] }>('/api/plugins')
      setPlugins(d.plugins)
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function handleDelete(plugin: Plugin) {
    if (!confirm(`Delete plugin "${plugin.filename}"? This cannot be undone.`)) return
    try {
      const res = await apiFetch(`/api/plugins/${encodeURIComponent(plugin.filename)}`, { method: 'DELETE' })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      notify.success(`${plugin.filename} deleted`)
      load()
    } catch (e) {
      notify.error(errorMessage(e))
    }
  }

  return (
    <Layout>
      <div className="p-6">
        <PageHeader
          eyebrow="CONTENT / PLUGINS"
          title="Plugins"
          count={plugins.length}
          countLabel="plugins"
          actions={
            canManage && (
              <button onClick={() => setShowUpload(true)}
                className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm rounded-none transition-colors">
                <Upload size={14} /> Upload APK
              </button>
            )
          }
        />

        <div className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 hud-glass">
          <HudCorners />
          <div className="overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-100 dark:bg-[#141416] text-zinc-600 dark:text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium hud-label text-xs">File</th>
                <th className="px-4 py-3 text-left font-medium hud-label text-xs">Size</th>
                <th className="px-4 py-3 text-left font-medium hud-label text-xs">SHA-256</th>
                <th className="px-4 py-3 text-right font-medium hud-label text-xs">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-200 dark:divide-white/10">
              {loading ? (
                <TableSkeletonRows columns={4} />
              ) : plugins.length === 0 ? (
                <tr className="bg-zinc-50 dark:bg-[#0c0c0e]"><td colSpan={4} className="px-4 py-8 text-center text-zinc-500">No plugins uploaded</td></tr>
              ) : (
                plugins.map(p => (
                  <tr key={p.filename} className="bg-zinc-50 dark:bg-[#000000] hover:bg-zinc-100/50 dark:hover:bg-white/[0.03]">
                    <td className="px-4 py-3 font-mono">{p.filename}</td>
                    <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">{p.size}</td>
                    <td className="px-4 py-3">{p.sha256 ? <CopyHash hash={p.sha256} /> : <span className="text-zinc-400 dark:text-zinc-600 text-xs">—</span>}</td>
                    <td className="px-4 py-3">
                      {canManage && (
                        <div className="flex justify-end">
                          <button onClick={() => handleDelete(p)} className="p-1.5 rounded-none hover:bg-zinc-200 dark:hover:bg-[#141416] text-red-600 dark:text-red-400 focus:outline-none focus:ring-2 focus:ring-accent-ring" title="Delete" aria-label="Delete">
                            <Trash2 size={14} />
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
          </div>
        </div>
      </div>
      {showUpload && <UploadModal onClose={() => setShowUpload(false)} onUploaded={load} />}
    </Layout>
  )
}
