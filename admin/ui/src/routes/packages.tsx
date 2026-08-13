import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { apiJson, apiFetch, downloadFile, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { notify } from '@/lib/notify'
import { TableSkeletonRows } from '@/components/Skeleton'
import { HudCorners } from '@/components/HudCorners'
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
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<Package | null>(null)
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)
  const [fieldResult, setFieldResult] = useState<{ username: string; password: string | null; created: boolean } | null>(null)

  async function handleCreateFieldLogin(pkg: Package) {
    try {
      const res = await apiJson<{ field_username: string; field_account_password: string | null; field_account_created: boolean }>(
        `/api/users/create-field-login/${encodeURIComponent(pkg.name)}`, { method: 'POST' }
      )
      setFieldResult({ username: res.field_username, password: res.field_account_password, created: res.field_account_created })
    } catch (e) {
      notify.error(errorMessage(e))
    }
  }

  async function load() {
    try {
      const data = await apiJson<{ packages: Package[] }>('/api/packages')
      setPackages(data.packages)
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setLoading(false)
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
      notify.success(`${file.name} uploaded`)
      load()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setUploading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  async function handleDownload(pkg: Package) {
    try {
      await downloadFile(`/api/packages/${encodeURIComponent(pkg.name)}/download`, pkg.filename)
    } catch (e) {
      notify.error(errorMessage(e))
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
      notify.success(`${pkg.name} deleted`)
      if (selected?.name === pkg.name) setSelected(null)
      load()
    } catch (e) {
      notify.error(errorMessage(e))
    }
  }

  return (
    <Layout>
      <div className="p-6">
        <PageHeader
          eyebrow="CONTENT / PACKAGES"
          title="Data Packages"
          count={packages.length}
          countLabel="packages"
          actions={
            <button
              onClick={() => fileRef.current?.click()}
              disabled={uploading}
              className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover disabled:opacity-50 text-accent-text text-sm rounded-none transition-colors"
            >
              <Upload size={14} />
              {uploading ? 'Uploading…' : 'Upload Package'}
            </button>
          }
        />
        <input
          ref={fileRef}
          type="file"
          accept=".zip"
          className="hidden"
          onChange={handleUpload}
        />

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <div className="hud-frame relative lg:col-span-2 rounded-none border border-zinc-200 dark:border-white/10 hud-glass">
            <HudCorners />
            <div className="overflow-x-auto">
            <table className="w-full text-sm min-w-[480px]">
              <thead className="bg-zinc-100 dark:bg-[#141416] text-zinc-600 dark:text-zinc-400">
                <tr>
                  <th className="px-4 py-3 text-left font-medium hud-label text-xs">Name</th>
                  <th className="px-4 py-3 text-left font-medium hud-label text-xs">Size</th>
                  <th className="px-4 py-3 text-right font-medium hud-label text-xs">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-200 dark:divide-white/10">
                {loading ? (
                  <TableSkeletonRows columns={3} />
                ) : packages.length === 0 ? (
                  <tr className="bg-zinc-50 dark:bg-[#0c0c0e]">
                    <td colSpan={3} className="px-4 py-8 text-center text-zinc-500">
                      No packages yet — upload one
                    </td>
                  </tr>
                ) : (
                  packages.map(p => (
                    <tr
                      key={p.name}
                      onClick={() => { setSelected(p); setFieldResult(null) }}
                      className={`bg-zinc-50 dark:bg-[#000000] hover:bg-zinc-100/50 dark:hover:bg-white/[0.03] cursor-pointer ${selected?.name === p.name ? 'ring-1 ring-inset ring-accent-fill' : ''}`}
                    >
                      <td className="px-4 py-3 font-mono">{p.name}</td>
                      <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">{p.size}</td>
                      <td className="px-4 py-3">
                        <div className="flex justify-end gap-1">
                          <button
                            onClick={e => { e.stopPropagation(); handleDownload(p) }}
                            className="p-1.5 rounded-none hover:bg-zinc-200 dark:hover:bg-[#141416] text-accent-ring"
                            title="Download"
                          >
                            <Download size={14} />
                          </button>
                          <button
                            onClick={e => { e.stopPropagation(); handleDelete(p) }}
                            className="p-1.5 rounded-none hover:bg-zinc-200 dark:hover:bg-[#141416] text-red-600 dark:text-red-400"
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

          <div className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 bg-zinc-100 dark:bg-[#0c0c0e] p-4 flex flex-col items-center gap-4 min-h-[200px] justify-center">
            <HudCorners />
            {selected ? (
              <>
                <p className="text-sm font-medium text-zinc-700 dark:text-zinc-300 text-center break-all">{selected.name}</p>
                <p className="text-xs text-zinc-600 dark:text-zinc-400 text-center break-all">{selected.filename}</p>
                <p className="text-xs text-zinc-500 text-center break-all">{selected.size}</p>
                <button onClick={() => handleDownload(selected)} className="text-xs text-accent-ring hover:underline break-all text-center">
                  Download
                </button>
                {role !== 'field' && (
                  <button
                    onClick={() => handleCreateFieldLogin(selected)}
                    className="text-xs px-3 py-1.5 rounded-none bg-zinc-200 dark:bg-[#141416] hover:bg-zinc-300 dark:hover:bg-[#232326] text-zinc-700 dark:text-zinc-300"
                  >
                    Create field login
                  </button>
                )}
                {fieldResult && (
                  <div className="p-2 rounded-none border border-yellow-300 dark:border-yellow-700/50 bg-yellow-50 dark:bg-yellow-900/20 text-xs text-left space-y-1 w-full">
                    {fieldResult.created ? (
                      <>
                        <p className="text-yellow-800 dark:text-yellow-200">Field login created — shown once:</p>
                        <p className="font-mono">user: {fieldResult.username}</p>
                        <p className="font-mono">pass: {fieldResult.password}</p>
                      </>
                    ) : (
                      <p className="text-zinc-600 dark:text-zinc-400">Login already exists for "{fieldResult.username}" — no new password.</p>
                    )}
                  </div>
                )}
              </>
            ) : (
              <p className="text-sm text-zinc-400 dark:text-zinc-600">Select a package to view details</p>
            )}
          </div>
        </div>
      </div>
    </Layout>
  )
}
