import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { Download, Trash2, Upload } from 'lucide-react'

export const Route = createFileRoute('/packages')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: PackagesPage,
})

interface Package {
  name: string
  filename: string
  size: string
  url?: string
}

function PackagesPage() {
  const [packages, setPackages] = useState<Package[]>([])
  const [selected, setSelected] = useState<Package | null>(null)
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  async function load() {
    try {
      const data = await apiJson<{ packages: Package[] }>('/api/packages')
      setPackages(data.packages)
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
      const res = await apiFetch('/api/packages/upload', { method: 'POST', body: form })
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

  async function handleDelete(pkg: Package) {
    if (!confirm(`Delete package "${pkg.name}"? This cannot be undone.`)) return
    try {
      const res = await apiFetch(`/api/packages/${encodeURIComponent(pkg.name)}`, { method: 'DELETE' })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      toast.success(`${pkg.name} deleted`)
      if (selected?.name === pkg.name) setSelected(null)
      load()
    } catch (e: any) {
      toast.error(e.message)
    }
  }

  return (
    <Layout>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-xl font-semibold">Data Packages</h1>
          <button
            onClick={() => fileRef.current?.click()}
            disabled={uploading}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white text-sm rounded-md transition-colors"
          >
            <Upload size={14} />
            {uploading ? 'Uploading…' : 'Upload Package'}
          </button>
          <input
            ref={fileRef}
            type="file"
            accept=".zip"
            className="hidden"
            onChange={handleUpload}
          />
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <div className="lg:col-span-2 rounded-lg border border-zinc-800 overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-zinc-900 text-zinc-400">
                <tr>
                  <th className="px-4 py-3 text-left font-medium">Name</th>
                  <th className="px-4 py-3 text-left font-medium">Size</th>
                  <th className="px-4 py-3 text-right font-medium">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-800">
                {packages.length === 0 && (
                  <tr>
                    <td colSpan={3} className="px-4 py-8 text-center text-zinc-500">
                      No packages yet — upload one
                    </td>
                  </tr>
                )}
                {packages.map(p => (
                  <tr
                    key={p.name}
                    onClick={() => setSelected(p)}
                    className={`bg-zinc-950 hover:bg-zinc-900/50 cursor-pointer ${selected?.name === p.name ? 'ring-1 ring-inset ring-blue-600' : ''}`}
                  >
                    <td className="px-4 py-3 font-mono">{p.name}</td>
                    <td className="px-4 py-3 text-zinc-400">{p.size}</td>
                    <td className="px-4 py-3">
                      <div className="flex justify-end gap-1">
                        {p.url && (
                          <a
                            href={p.url}
                            onClick={e => e.stopPropagation()}
                            download
                            className="p-1.5 rounded hover:bg-zinc-800 text-blue-400"
                            title="Download"
                          >
                            <Download size={14} />
                          </a>
                        )}
                        <button
                          onClick={e => { e.stopPropagation(); handleDelete(p) }}
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

          <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4 flex flex-col items-center gap-4 min-h-[200px] justify-center">
            {selected ? (
              <>
                <p className="text-sm font-medium text-zinc-300 text-center break-all">{selected.name}</p>
                <p className="text-xs text-zinc-400 text-center break-all">{selected.filename}</p>
                <p className="text-xs text-zinc-500 text-center break-all">{selected.size}</p>
                {selected.url && (
                  <a href={selected.url} download className="text-xs text-blue-400 hover:underline break-all text-center">
                    {selected.url}
                  </a>
                )}
              </>
            ) : (
              <p className="text-sm text-zinc-600">Select a package to view details</p>
            )}
          </div>
        </div>
      </div>
    </Layout>
  )
}
