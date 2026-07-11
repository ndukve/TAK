import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { apiJson, apiFetch, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { notify } from '@/lib/notify'
import { Play, Square, Settings2 } from 'lucide-react'

export const Route = createFileRoute('/replay')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: ReplayPage,
})

interface Status {
  service_cert_ready: boolean
  recording: boolean
  current_chunk_id: string | null
  playback: boolean
  settings: { max_disk_mb: number; min_free_disk_mb: number; chunk_minutes: number }
}

interface Chunk {
  id: string
  started_at: string
  ended_at: string | null
  event_count: number
  size_bytes: number
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function ReplayPage() {
  const [status, setStatus] = useState<Status | null>(null)
  const [chunks, setChunks] = useState<Chunk[]>([])
  const [speed, setSpeed] = useState(1)
  const [busy, setBusy] = useState(false)

  async function load() {
    try {
      const [s, c] = await Promise.all([
        apiJson<Status>('/api/replay/status'),
        apiJson<{ chunks: Chunk[] }>('/api/replay/chunks'),
      ])
      setStatus(s)
      setChunks(c.chunks)
    } catch (e) {
      notify.error(errorMessage(e))
    }
  }

  useEffect(() => {
    load()
    const id = setInterval(load, 5000)
    return () => clearInterval(id)
  }, [])

  async function handleSetup() {
    setBusy(true)
    try {
      const res = await apiFetch('/api/replay/setup', { method: 'POST' })
      if (!res.ok) throw new Error((await res.json()).detail ?? 'Setup failed')
      notify.success('Service certificate ready')
      await load()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  async function handleStartRecording() {
    setBusy(true)
    try {
      const res = await apiFetch('/api/replay/start', { method: 'POST' })
      if (!res.ok) throw new Error((await res.json()).detail ?? 'Failed to start')
      notify.success('Recording started')
      await load()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  async function handleStopRecording() {
    setBusy(true)
    try {
      const res = await apiFetch('/api/replay/stop', { method: 'POST' })
      if (!res.ok) throw new Error((await res.json()).detail ?? 'Failed to stop')
      notify.success('Recording stopped')
      await load()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  async function handlePlay(chunkId: string) {
    setBusy(true)
    try {
      const res = await apiFetch(`/api/replay/chunks/${chunkId}/play`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ speed }),
      })
      if (!res.ok) throw new Error((await res.json()).detail ?? 'Failed to play')
      notify.success('Playback started')
      await load()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  async function handleStopPlayback() {
    setBusy(true)
    try {
      await apiFetch('/api/replay/stop-playback', { method: 'POST' })
      notify.success('Playback stopped')
      await load()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  if (!status) return <Layout><div className="p-6">Loading…</div></Layout>

  return (
    <Layout>
      <div className="p-6">
        <PageHeader title="Replay Mode" />

        {!status.service_cert_ready ? (
          <div className="rounded-md border border-zinc-200 dark:border-white/10 bg-white dark:bg-[#111113] p-6">
            <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-4">
              Replay Mode needs a dedicated service certificate to connect to the TAK server. Set it up once before recording.
            </p>
            <button onClick={handleSetup} disabled={busy}
              className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm rounded-md disabled:opacity-50 transition-colors">
              <Settings2 size={14} /> Set Up Replay
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="rounded-md border border-zinc-200 dark:border-white/10 bg-white dark:bg-[#111113] p-4">
              <h2 className="hud-label text-xs text-zinc-500 dark:text-zinc-400 mb-3">Recording</h2>
              <p className="text-sm text-zinc-700 dark:text-zinc-300 mb-3">
                {status.recording ? `Recording — chunk ${status.current_chunk_id}` : 'Not recording'}
              </p>
              {status.recording ? (
                <button onClick={handleStopRecording} disabled={busy}
                  className="flex items-center gap-2 px-4 py-2 bg-red-600 hover:bg-red-700 text-white text-sm rounded-md disabled:opacity-50 transition-colors">
                  <Square size={14} /> Stop Recording
                </button>
              ) : (
                <button onClick={handleStartRecording} disabled={busy}
                  className="flex items-center gap-2 px-4 py-2 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm rounded-md disabled:opacity-50 transition-colors">
                  <Play size={14} /> Start Recording
                </button>
              )}
            </div>

            <div className="rounded-md border border-zinc-200 dark:border-white/10 bg-white dark:bg-[#111113] p-4">
              <h2 className="hud-label text-xs text-zinc-500 dark:text-zinc-400 mb-3">Playback</h2>
              <div className="flex items-center gap-2 mb-3">
                <span className="text-sm text-zinc-600 dark:text-zinc-400">Speed:</span>
                {[1, 2, 5, 10].map(s => (
                  <button key={s} onClick={() => setSpeed(s)} disabled={status.playback}
                    className={`px-2 py-1 rounded text-xs disabled:opacity-50 ${speed === s ? 'bg-accent-fill text-accent-text' : 'bg-zinc-200 dark:bg-[#1a1a1d] text-zinc-700 dark:text-zinc-300'}`}>
                    {s}x
                  </button>
                ))}
              </div>
              {status.playback && (
                <button onClick={handleStopPlayback} disabled={busy}
                  className="flex items-center gap-2 px-4 py-2 bg-red-600 hover:bg-red-700 text-white text-sm rounded-md disabled:opacity-50 transition-colors mb-3">
                  <Square size={14} /> Stop Playback
                </button>
              )}
              <div className="divide-y divide-zinc-200 dark:divide-white/10 max-h-64 overflow-y-auto">
                {chunks.length === 0 ? (
                  <p className="text-sm text-zinc-500 py-4 text-center">No recorded chunks yet</p>
                ) : (
                  chunks.map(c => (
                    <div key={c.id} className="flex items-center justify-between py-2">
                      <div>
                        <p className="text-sm font-mono text-zinc-700 dark:text-zinc-300">{new Date(c.started_at).toLocaleString()}</p>
                        <p className="text-xs text-zinc-500">{c.event_count} events · {formatSize(c.size_bytes)}</p>
                      </div>
                      <button onClick={() => handlePlay(c.id)} disabled={status.playback || busy}
                        className="p-1.5 rounded hover:bg-zinc-200 dark:hover:bg-white/[0.05] text-accent-ring disabled:opacity-50 focus:outline-none focus:ring-2 focus:ring-accent-ring"
                        title="Play" aria-label={`Play chunk from ${new Date(c.started_at).toLocaleString()}`}>
                        <Play size={14} />
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>
        )}
      </div>
    </Layout>
  )
}
