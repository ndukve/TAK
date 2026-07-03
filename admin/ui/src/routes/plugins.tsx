import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiFetch, apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { Trash2, Upload, Copy, Check } from 'lucide-react'

export const Route = createFileRoute('/plugins')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role === 'field') throw redirect({ to: '/packages' })
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
    <button onClick={copy} title="Copy SHA-256" className="flex items-center gap-1 font-mono text-xs text-zinc-500 hover:text-zinc-300 transition-colors">
      <span>{hash.slice(0, 16)}…</span>
      {copied ? <Check size={11} className="text-green-400" /> : <Copy size={11} />}
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
      toast.success(`${file.name} uploaded — SHA-256: ${data.sha256?.slice(0, 16)}…`)
      onUploaded()
      onClose()
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-zinc-900 border border-zinc-700 rounded-lg p-6 w-full max-w-md">
        <h2 className="text-lg font-semibold mb-4">Upload Plugin</h2>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <input ref={fileRef} type="file" accept=".apk,.zip" className="hidden"
              onChange={e => setFile(e.target.files?.[0] ?? null)} />
            <button type="button" onClick={() => fileRef.current?.click()}
              className="w-full py-8 border-2 border-dashed border-zinc-700 rounded-lg text-zinc-400 hover:border-zinc-500 hover:text-zinc-200 transition-colors text-sm">
              {file ? file.name : 'Click to select .apk or .zip'}
            </button>
          </div>
          <div className="space-y-1">
            <label className="text-xs text-zinc-400">Expected SHA-256 (optional — from tak.gov)</label>
            <input type="text" value={expectedHash} onChange={e => setExpectedHash(e.target.value)}
              placeholder="e.g. a3f2c1…"
              className="w-full bg-zinc-800 border border-zinc-700 rounded px-3 py-2 text-xs font-mono" />
            <p className="text-xs text-zinc-500">If provided, upload is rejected if hash doesn't match.</p>
          </div>
          <div className="flex gap-2">
            <button type="button" onClick={onClose} className="flex-1 py-2 rounded bg-zinc-700 hover:bg-zinc-600 text-sm">Cancel</button>
            <button type="submit" disabled={!file || uploading}
              className="flex-1 py-2 rounded bg-accent-fill hover:bg-accent-fill-hover text-accent-text disabled:opacity-50 text-sm">
              {uploading ? 'Uploading…' : 'Upload'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function PluginsPage() {
  const [plugins, setPlugins] = useState<Plugin[]>([])
  const [showUpload, setShowUpload] = useState(false)

  async function load() {
    try {
      const d = await apiJson<{ plugins: Plugin[] }>('/api/plugins')
      setPlugins(d.plugins)
    } catch (e: any) {
      toast.error(e.message)
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
          <button onClick={() => setShowUpload(true)}
            className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm rounded-md transition-colors">
            <Upload size={14} /> Upload APK
          </button>
        </div>

        <div className="rounded-lg border border-zinc-800 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">File</th>
                <th className="px-4 py-3 text-left font-medium">Size</th>
                <th className="px-4 py-3 text-left font-medium">SHA-256</th>
                <th className="px-4 py-3 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {plugins.length === 0 && (
                <tr><td colSpan={4} className="px-4 py-8 text-center text-zinc-500">No plugins uploaded</td></tr>
              )}
              {plugins.map(p => (
                <tr key={p.filename} className="bg-zinc-950 hover:bg-zinc-900/50">
                  <td className="px-4 py-3 font-mono">{p.filename}</td>
                  <td className="px-4 py-3 text-zinc-400">{p.size}</td>
                  <td className="px-4 py-3">{p.sha256 ? <CopyHash hash={p.sha256} /> : <span className="text-zinc-600 text-xs">—</span>}</td>
                  <td className="px-4 py-3">
                    <div className="flex justify-end">
                      <button onClick={() => handleDelete(p)} className="p-1.5 rounded hover:bg-zinc-800 text-red-400" title="Delete">
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
      {showUpload && <UploadModal onClose={() => setShowUpload(false)} onUploaded={load} />}
    </Layout>
  )
}
