import { createFileRoute, redirect } from '@tanstack/react-router'
import { Icon } from '@/components/ui/icon'
import { useEffect, useRef, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { apiJson, apiFetch, downloadFileStreamed, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { notify } from '@/lib/notify'
import { TableSkeletonRows } from '@/components/Skeleton'
import { HudCorners } from '@/components/HudCorners'

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
      {copied ? <Icon name="check-line" size={11} className="text-green-600 dark:text-green-400" /> : <Icon name="file-copy-line" size={11} />}
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

interface UploadProgress {
  filename: string
  provider: string
  uploaded: number
  total: number
  phase: 'uploading' | 'paused' | 'failed' | 'complete'
  error?: string
}

interface UploadResponse {
  offset: number
  complete: boolean
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 ** 3) return `${(bytes / 1024 ** 2).toFixed(1)} MB`
  return `${(bytes / 1024 ** 3).toFixed(2)} GB`
}

function MapsPage() {
  const [maps, setMaps] = useState<MapSource[]>([])
  const [loading, setLoading] = useState(true)
  const [uploadProgress, setUploadProgress] = useState<UploadProgress | null>(null)
  const [provider, setProvider] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)
  const uploadFileRef = useRef<File | null>(null)
  const uploadAbortRef = useRef<AbortController | null>(null)

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
    const selectedProvider = provider.trim()
    uploadFileRef.current = file
    setUploadProgress({
      filename: file.name,
      provider: selectedProvider,
      uploaded: 0,
      total: file.size,
      phase: 'uploading',
    })
    if (fileRef.current) fileRef.current.value = ''
    void uploadMap(file, selectedProvider)
  }

  async function uploadMap(file: File, selectedProvider: string) {
    const controller = new AbortController()
    uploadAbortRef.current = controller
    const fingerprint = `${file.size}:${file.lastModified}`
    try {
      const initialized = await apiJson<UploadResponse>('/api/maps/uploads', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          provider: selectedProvider,
          filename: file.name,
          total_size: file.size,
          fingerprint,
        }),
        signal: controller.signal,
      })
      let offset = initialized.offset
      setUploadProgress(current => current ? { ...current, uploaded: offset, phase: 'uploading', error: undefined } : null)

      if (!initialized.complete) {
        const chunkSize = 2 * 1024 * 1024
        while (offset < file.size) {
          const end = Math.min(offset + chunkSize, file.size)
          const result = await apiJson<UploadResponse>(
            `/api/maps/uploads/${encodeURIComponent(selectedProvider)}/${encodeURIComponent(file.name)}?offset=${offset}&total_size=${file.size}&fingerprint=${encodeURIComponent(fingerprint)}`,
            {
              method: 'PUT',
              headers: { 'Content-Type': 'application/octet-stream' },
              body: file.slice(offset, end),
              signal: controller.signal,
            },
          )
          offset = result.offset
          setUploadProgress(current => current ? { ...current, uploaded: offset } : null)
        }
      }

      if (uploadAbortRef.current !== controller) return
      setUploadProgress(current => current ? { ...current, uploaded: file.size, phase: 'complete' } : null)
      notify.success(`${file.name} uploaded`)
      await load()
    } catch (e) {
      if (uploadAbortRef.current !== controller) return
      if (e instanceof DOMException && e.name === 'AbortError') {
        setUploadProgress(current => current ? { ...current, phase: 'paused' } : null)
      } else {
        const message = errorMessage(e)
        setUploadProgress(current => current ? { ...current, phase: 'failed', error: message } : null)
        notify.error(message)
      }
    } finally {
      if (uploadAbortRef.current === controller) uploadAbortRef.current = null
    }
  }

  function pauseUpload() {
    uploadAbortRef.current?.abort()
  }

  function resumeUpload() {
    const file = uploadFileRef.current
    if (!file || !uploadProgress) return
    setUploadProgress(current => current ? { ...current, phase: 'uploading', error: undefined } : null)
    void uploadMap(file, uploadProgress.provider)
  }

  function closeUploadPrompt() {
    uploadAbortRef.current?.abort()
    uploadAbortRef.current = null
    uploadFileRef.current = null
    setUploadProgress(null)
  }

  async function handleDownload(m: MapSource) {
    try {
      await downloadFileStreamed(`/api/maps/${encodeURIComponent(m.provider)}/${encodeURIComponent(m.filename)}/download`, m.filename)
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
        <PageHeader eyebrow="CONTENT / MAP SOURCES" title="Map Sources" />
        <div className="flex items-center gap-3 mb-6">
          <input
            type="text"
            placeholder="Provider (e.g. Google)"
            value={provider}
            onChange={e => setProvider(e.target.value)}
            className="px-3 py-2 bg-zinc-100 dark:bg-[#0c0c0e] border border-zinc-300 dark:border-white/10 rounded-none text-sm text-zinc-900 dark:text-white placeholder-zinc-500 w-48"
          />
          <button
            onClick={handleUploadClick}
            disabled={uploadProgress !== null}
            className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover disabled:opacity-50 text-accent-text text-sm rounded-none transition-colors"
          >
            <Icon name="upload-line" size={14} />
            {uploadProgress?.phase === 'uploading' ? 'Uploading…' : 'Upload Map'}
          </button>
          <input
            ref={fileRef}
            type="file"
            accept=".xml,.mbtiles"
            className="hidden"
            onChange={handleUpload}
          />
          {maps.length > 0 && (
            <button
              onClick={() => downloadFileStreamed('/api/maps/download-all', 'maps.zip').catch((e) => notify.error(errorMessage(e)))}
              className="flex items-center gap-2 px-4 py-2 bg-zinc-200 dark:bg-[#141416] hover:bg-zinc-300 dark:hover:bg-[#232326] text-zinc-700 dark:text-zinc-300 text-sm rounded-none transition-colors"
            >
              <Icon name="download-line" size={14} />
              Download All ({maps.length})
            </button>
          )}
        </div>

        <div className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 hud-glass">
          <HudCorners />
          <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[600px]">
            <thead className="bg-zinc-100 dark:bg-[#141416] text-zinc-600 dark:text-zinc-400">
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
                <tr className="bg-zinc-50 dark:bg-[#0c0c0e]">
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
                      <span className={`px-1.5 py-0.5 rounded-none text-xs font-mono ${m.kind === 'mbtiles' ? 'bg-accent-fill/20 text-accent-ring' : 'bg-zinc-200 dark:bg-white/10 text-zinc-600 dark:text-zinc-400'}`}>
                        {m.kind === 'mbtiles' ? 'offline' : 'xml'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">{m.size}</td>
                    <td className="px-4 py-3">{m.sha256 ? <CopyHash hash={m.sha256} /> : <span className="text-zinc-400 dark:text-zinc-600 text-xs">—</span>}</td>
                    <td className="px-4 py-3">
                      <div className="flex justify-end gap-1">
                        <button
                          onClick={() => handleDownload(m)}
                          className="p-1.5 rounded-none hover:bg-zinc-200 dark:hover:bg-[#141416] text-accent-ring"
                          title="Download"
                        >
                          <Icon name="download-line" size={14} />
                        </button>
                        <button
                          onClick={() => handleDelete(m)}
                          className="p-1.5 rounded-none hover:bg-zinc-200 dark:hover:bg-[#141416] text-red-600 dark:text-red-400"
                          title="Delete"
                        >
                          <Icon name="delete-bin-2-line" size={14} />
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

        {uploadProgress && (
          <div className="fixed inset-0 z-[1000] flex items-center justify-center bg-black/65 px-4" role="dialog" aria-modal="true" aria-labelledby="map-upload-title">
            <div className="w-full max-w-md rounded-none border border-zinc-300 dark:border-white/15 hud-glass p-5 shadow-2xl">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <h2 id="map-upload-title" className="text-base font-semibold text-zinc-900 dark:text-white">Map upload</h2>
                  <p className="mt-1 truncate font-mono text-xs text-zinc-500">{uploadProgress.provider}/{uploadProgress.filename}</p>
                </div>
                <button onClick={closeUploadPrompt} className="rounded-none p-1 text-zinc-500 hover:bg-zinc-100 dark:hover:bg-white/10" aria-label="Close upload dialog">
                  <Icon name="close-line" size={16} />
                </button>
              </div>

              <div className="mt-5 h-2 overflow-hidden rounded-full bg-zinc-200 dark:bg-white/10">
                <div
                  className={`h-full transition-[width] duration-200 ${uploadProgress.phase === 'failed' ? 'bg-red-500' : 'bg-accent-fill'}`}
                  style={{ width: `${uploadProgress.total ? Math.min(100, (uploadProgress.uploaded / uploadProgress.total) * 100) : 0}%` }}
                />
              </div>
              <div className="mt-2 flex justify-between text-xs text-zinc-500">
                <span>{formatBytes(uploadProgress.uploaded)} of {formatBytes(uploadProgress.total)}</span>
                <span>{uploadProgress.total ? Math.floor((uploadProgress.uploaded / uploadProgress.total) * 100) : 0}%</span>
              </div>

              <p className={`mt-4 text-sm ${uploadProgress.phase === 'failed' ? 'text-red-600 dark:text-red-400' : 'text-zinc-600 dark:text-zinc-300'}`}>
                {uploadProgress.phase === 'uploading' && 'Uploading in resumable chunks…'}
                {uploadProgress.phase === 'paused' && 'Upload paused. Resume continues from the last stored chunk.'}
                {uploadProgress.phase === 'failed' && (uploadProgress.error ?? 'Upload interrupted. You can resume it.')}
                {uploadProgress.phase === 'complete' && 'Upload complete.'}
              </p>

              <div className="mt-5 flex justify-end gap-2">
                {uploadProgress.phase === 'uploading' && (
                  <button onClick={pauseUpload} className="flex items-center gap-2 rounded-none border border-zinc-300 dark:border-white/15 px-3 py-2 text-sm hover:bg-zinc-100 dark:hover:bg-white/10">
                    <Icon name="pause-line" size={14} /> Pause
                  </button>
                )}
                {(uploadProgress.phase === 'paused' || uploadProgress.phase === 'failed') && (
                  <button onClick={resumeUpload} className="flex items-center gap-2 rounded-none bg-accent-fill px-3 py-2 text-sm text-accent-text hover:bg-accent-fill-hover">
                    <Icon name="arrow-go-back-line" size={14} /> Resume upload
                  </button>
                )}
                {uploadProgress.phase === 'complete' && (
                  <button onClick={closeUploadPrompt} className="rounded-none bg-accent-fill px-3 py-2 text-sm text-accent-text hover:bg-accent-fill-hover">Close</button>
                )}
              </div>
            </div>
          </div>
        )}
      </div>
    </Layout>
  )
}
