import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson, apiFetch, downloadFile } from '@/lib/api'
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
}

function PackagesPage() {
  const { role } = useAuth()
  const [packages, setPackages] = useState<Package[]>([])
  const [selected, setSelected] = useState<Package | null>(null)
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)
  const [fieldResult, setFieldResult] = useState<{ username: string; password: string | null; created: boolean } | null>(null)

  async function handleCreateFieldLogin(pkg: Package) {
    try {
      const res = await apiJson<any>(`/api/users/create-field-login/${encodeURIComponent(pkg.name)}`, { method: 'POST' })
      setFieldResult({ username: res.field_username, password: res.field_account_password, created: res.field_account_created })
    } catch (e: any) {
      toast.error(e.message)
    }
  }

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

  async function handleDownload(pkg: Package) {
    try {
      await downloadFile(`/api/packages/${encodeURIComponent(pkg.name)}/download`, pkg.filename)
    } catch (e: any) {
      toast.error(e.message)
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
            className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover disabled:opacity-50 text-accent-text text-sm rounded-md transition-colors"
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
          <div className="lg:col-span-2 rounded-lg border border-zinc-800 overflow-x-auto">
            <table className="w-full text-sm min-w-[480px]">
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
                    onClick={() => { setSelected(p); setFieldResult(null) }}
                    className={`bg-zinc-950 hover:bg-zinc-900/50 cursor-pointer ${selected?.name === p.name ? 'ring-1 ring-inset ring-accent-fill' : ''}`}
                  >
                    <td className="px-4 py-3 font-mono">{p.name}</td>
                    <td className="px-4 py-3 text-zinc-400">{p.size}</td>
                    <td className="px-4 py-3">
                      <div className="flex justify-end gap-1">
                        <button
                          onClick={e => { e.stopPropagation(); handleDownload(p) }}
                          className="p-1.5 rounded hover:bg-zinc-800 text-accent-ring"
                          title="Download"
                        >
                          <Download size={14} />
                        </button>
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
                <button onClick={() => handleDownload(selected)} className="text-xs text-accent-ring hover:underline break-all text-center">
                  Download
                </button>
                {role !== 'field' && (
                  <button
                    onClick={() => handleCreateFieldLogin(selected)}
                    className="text-xs px-3 py-1.5 rounded bg-zinc-800 hover:bg-zinc-700 text-zinc-300"
                  >
                    Create field login
                  </button>
                )}
                {fieldResult && (
                  <div className="p-2 rounded border border-yellow-700/50 bg-yellow-900/20 text-xs text-left space-y-1 w-full">
                    {fieldResult.created ? (
                      <>
                        <p className="text-yellow-200">Field login created — shown once:</p>
                        <p className="font-mono">user: {fieldResult.username}</p>
                        <p className="font-mono">pass: {fieldResult.password}</p>
                      </>
                    ) : (
                      <p className="text-zinc-400">Login already exists for "{fieldResult.username}" — no new password.</p>
                    )}
                  </div>
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
