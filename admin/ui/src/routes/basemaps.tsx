import { createFileRoute, redirect } from '@tanstack/react-router'
import { useCallback, useEffect, useRef, useState } from 'react'
import { AlertTriangle, CheckCircle2, CloudRain, FileUp, History, Radio, RefreshCw, RotateCcw, Send, Trash2, Upload } from 'lucide-react'
import { Layout } from '@/components/Layout'
import { PageHeader } from '@/components/PageHeader'
import { HudCorners } from '@/components/HudCorners'
import { apiJson, errorMessage } from '@/lib/api'
import { notify } from '@/lib/notify'
import { useAuth } from '@/store/auth'

export const Route = createFileRoute('/basemaps')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: BasemapsPage,
})

interface CatalogEntry {
  id: string
  name: string
  description: string
}

interface Preset extends CatalogEntry {
  layer_count: number
  overlay_opacity: number
}

interface LibrarySource extends CatalogEntry {
  provider: string
  kind: 'xml' | 'offline'
  size_bytes?: number
}

type OfflineSource = CatalogEntry

interface Recipient {
  uid: string
  callsign: string
  group: string
}

interface PushResult {
  id: string
  request_id: string
  mission_name: string | null
  pushed_at: string
  layer_count: number
  recipient_count: number
  recipients: string[]
  recipient_uids: string[]
  status: string
  accepted_count: number
  error?: string | null
  created_at: string
}

interface SourceHealth {
  id: string
  status: 'healthy' | 'unhealthy'
  latency_ms: number
  content_type?: string
  error?: string
}

interface ProxyStatus {
  enabled: boolean
  public_url: string
  cache_max_mb: number
  ready: boolean
  warning: string | null
}

function BasemapsPage() {
  const [presets, setPresets] = useState<Preset[]>([])
  const [librarySources, setLibrarySources] = useState<LibrarySource[]>([])
  const [offlineSources, setOfflineSources] = useState<OfflineSource[]>([])
  const [providerNotice, setProviderNotice] = useState('')
  const [proxyStatus, setProxyStatus] = useState<ProxyStatus | null>(null)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [recipients, setRecipients] = useState<Recipient[]>([])
  const [selectedRecipients, setSelectedRecipients] = useState<Set<string>>(new Set())
  const [allRecipients, setAllRecipients] = useState(true)
  const [recipientError, setRecipientError] = useState('')
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [lastPush, setLastPush] = useState<PushResult | null>(null)
  const [history, setHistory] = useState<PushResult[]>([])
  const [health, setHealth] = useState<SourceHealth[]>([])
  const [overlayOpacity, setOverlayOpacity] = useState(70)
  const [fileName, setFileName] = useState('')
  const [urlName, setUrlName] = useState('')
  const [xmlUrl, setXmlUrl] = useState('')
  const [offlineName, setOfflineName] = useState('Lithuania AOI')
  const [offlineSource, setOfflineSource] = useState('esri-imagery')
  const [offlineBounds, setOfflineBounds] = useState({ west: '20.8', south: '53.8', east: '26.9', north: '56.5' })
  const [offlineZoom, setOfflineZoom] = useState({ min: '6', max: '10' })
  const fileRef = useRef<HTMLInputElement>(null)

  const loadCatalog = useCallback(async () => {
    const data = await apiJson<{
      presets: Preset[]
      library_sources: LibrarySource[]
      offline_sources: OfflineSource[]
      provider_notice: string
      proxy: ProxyStatus
    }>('/api/basemaps/catalog')
    setPresets(data.presets)
    setLibrarySources(data.library_sources)
    setOfflineSources(data.offline_sources)
    setProviderNotice(data.provider_notice)
    setProxyStatus(data.proxy)
  }, [])

  const loadHistory = useCallback(async () => {
    const data = await apiJson<{ distributions: PushResult[] }>('/api/basemaps/history')
    setHistory(data.distributions)
  }, [])

  const loadRecipients = useCallback(async () => {
    try {
      const data = await apiJson<{ recipients: Recipient[] }>('/api/basemaps/recipients')
      setRecipientError('')
      setRecipients(data.recipients)
      const current = new Set(data.recipients.map(recipient => recipient.uid))
      setSelectedRecipients(previous => new Set([...previous].filter(uid => current.has(uid))))
    } catch (error) {
      setRecipientError(errorMessage(error))
      throw error
    }
  }, [])

  const load = useCallback(async () => {
    try {
      await Promise.all([loadCatalog(), loadRecipients(), loadHistory()])
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setLoading(false)
    }
  }, [loadCatalog, loadHistory, loadRecipients])

  useEffect(() => {
    void load()
    const timer = window.setInterval(() => { void loadRecipients().catch(() => undefined) }, 5000)
    return () => window.clearInterval(timer)
  }, [load, loadRecipients])

  function toggleEntry(id: string) {
    setSelected(current => {
      const next = new Set(current)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function toggleRecipient(uid: string) {
    setAllRecipients(false)
    setSelectedRecipients(current => {
      const next = new Set(allRecipients ? recipients.map(recipient => recipient.uid) : current)
      if (next.has(uid)) next.delete(uid)
      else next.add(uid)
      return next
    })
  }

  function selectRecipientGroup(group: string) {
    setAllRecipients(false)
    setSelectedRecipients(new Set(recipients.filter(recipient => recipient.group === group).map(recipient => recipient.uid)))
  }

  async function setupConnection() {
    setBusy(true)
    try {
      await apiJson('/api/basemaps/setup', { method: 'POST' })
      await loadRecipients()
      notify.success('TAK Server client discovery is ready')
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function pushSelected() {
    const recipientUids = allRecipients
      ? recipients.map(recipient => recipient.uid)
      : [...selectedRecipients]
    if (selected.size === 0) {
      notify.error('Select at least one basemap or overlay')
      return
    }
    if (recipientUids.length === 0) {
      notify.error('No connected EUD recipients selected')
      return
    }
    setBusy(true)
    try {
      const result = await apiJson<PushResult>('/api/basemaps/push', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          item_ids: [...selected],
          recipient_uids: recipientUids,
          overlay_opacity: overlayOpacity,
          request_id: crypto.randomUUID(),
        }),
      })
      setLastPush(result)
      await loadHistory()
      notify.success(`${result.layer_count} layer${result.layer_count === 1 ? '' : 's'} pushed to ${result.recipient_count} EUD${result.recipient_count === 1 ? '' : 's'}`)
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function addXmlFile(event: React.FormEvent) {
    event.preventDefault()
    const file = fileRef.current?.files?.[0]
    if (!file) {
      notify.error('Choose an ATAK XML map source')
      return
    }
    const form = new FormData()
    form.append('name', fileName)
    form.append('file', file)
    setBusy(true)
    try {
      const result = await apiJson<{ id: string; name: string }>('/api/basemaps/custom/file', { method: 'POST', body: form })
      await loadCatalog()
      setSelected(current => new Set(current).add(result.id))
      setFileName('')
      if (fileRef.current) fileRef.current.value = ''
      notify.success(`${result.name} added`)
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function addXmlUrl(event: React.FormEvent) {
    event.preventDefault()
    setBusy(true)
    try {
      const result = await apiJson<{ id: string; name: string }>('/api/basemaps/custom/url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: urlName, url: xmlUrl }),
      })
      await loadCatalog()
      setSelected(current => new Set(current).add(result.id))
      setUrlName('')
      setXmlUrl('')
      notify.success(`${result.name} added`)
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function checkSources() {
    setBusy(true)
    try {
      const result = await apiJson<{ sources: SourceHealth[] }>('/api/basemaps/source-health')
      setHealth(result.sources)
      const failures = result.sources.filter(source => source.status === 'unhealthy').length
      if (failures) notify.error(`${failures} upstream source${failures === 1 ? '' : 's'} failed`)
      else notify.success('All upstream map sources are healthy')
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function buildOffline(event: React.FormEvent) {
    event.preventDefault()
    setBusy(true)
    try {
      const result = await apiJson<{ id: string; name: string; tile_count: number }>('/api/basemaps/offline/build', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: offlineName,
          source_id: offlineSource,
          west: Number(offlineBounds.west),
          south: Number(offlineBounds.south),
          east: Number(offlineBounds.east),
          north: Number(offlineBounds.north),
          min_zoom: Number(offlineZoom.min),
          max_zoom: Number(offlineZoom.max),
        }),
      })
      await loadCatalog()
      setSelected(current => new Set(current).add(result.id))
      notify.success(`${result.name} built with ${result.tile_count} offline tiles`)
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function removeLibrarySource(source: LibrarySource) {
    if (!confirm(`Delete stored source "${source.name}"?`)) return
    const relative = source.id.split(':', 2)[1]
    setBusy(true)
    try {
      await apiJson(`/api/basemaps/library/${relative}`, { method: 'DELETE' })
      setSelected(current => {
        const next = new Set(current)
        next.delete(source.id)
        return next
      })
      await loadCatalog()
      notify.success(`${source.name} deleted`)
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function refreshDelivery(distribution: PushResult) {
    setBusy(true)
    try {
      const result = await apiJson<PushResult>(`/api/basemaps/history/${distribution.id}/refresh`, { method: 'POST' })
      setHistory(current => current.map(entry => entry.id === result.id ? result : entry))
      notify.success(`${result.accepted_count} of ${result.recipient_count} recipients accepted`)
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function resend(distribution: PushResult) {
    setBusy(true)
    try {
      const result = await apiJson<PushResult>(`/api/basemaps/history/${distribution.id}/resend`, { method: 'POST' })
      setLastPush(result)
      await loadHistory()
      notify.success('Basemap mission resent')
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function removeDistribution(distribution: PushResult) {
    if (!confirm(`Delete basemap record "${distribution.mission_name ?? distribution.request_id}"?`)) return
    setBusy(true)
    try {
      await apiJson(`/api/basemaps/history/${distribution.id}`, { method: 'DELETE' })
      await loadHistory()
      notify.success('Basemap mission deleted')
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  async function cleanupHistory() {
    setBusy(true)
    try {
      const result = await apiJson<{ cleaned: number }>('/api/basemaps/cleanup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ older_than_days: 30 }),
      })
      await loadHistory()
      notify.success(`${result.cleaned} old mission${result.cleaned === 1 ? '' : 's'} cleaned`)
    } catch (error) {
      notify.error(errorMessage(error))
    } finally {
      setBusy(false)
    }
  }

  const recipientCount = allRecipients ? recipients.length : selectedRecipients.size
  const recipientGroups = [...new Set(recipients.map(recipient => recipient.group))].sort()

  return (
    <Layout>
      <div className="p-6 space-y-5">
        <PageHeader
          eyebrow="CONTENT / BASEMAPS"
          title="TAK Basemaps / Overlays"
          count={presets.length + librarySources.length}
          countLabel="entries"
        />

        {proxyStatus?.warning && (
          <div className="flex items-start gap-2 rounded-none border border-yellow-300/60 dark:border-yellow-600/30 bg-yellow-50 dark:bg-yellow-500/[0.05] p-3 text-xs text-yellow-800 dark:text-yellow-300">
            <AlertTriangle size={15} className="mt-0.5 shrink-0" />
            <span>{proxyStatus.warning}</span>
          </div>
        )}

        {lastPush && (
          <section className="hud-frame relative rounded-none border border-green-300 dark:border-green-500/40 bg-green-50 dark:bg-green-500/[0.06] p-4">
            <HudCorners />
            <div className="flex items-start gap-3">
              <CheckCircle2 size={19} className="mt-0.5 shrink-0 text-green-600 dark:text-green-400" />
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="rounded-none bg-green-600 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white">Successful</span>
                  <h2 className="text-sm font-semibold">TAK Basemaps / Overlays</h2>
                </div>
                <p className="mt-2 text-xs text-zinc-600 dark:text-zinc-300">
                  TAK Server sent mission <span className="font-mono">{lastPush.mission_name}</span> with {lastPush.layer_count} layers to {lastPush.recipient_count} connected EUDs.
                </p>
                <p className="mt-1 break-words font-mono text-[11px] text-zinc-500">
                  Recipients: {lastPush.recipients.join(', ')} · Pushed: {new Date(lastPush.pushed_at).toLocaleString()}
                </p>
              </div>
            </div>
          </section>
        )}

        <section className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 hud-glass p-4">
          <HudCorners />
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-zinc-200 dark:border-white/10 pb-3">
            <div>
              <h2 className="text-sm font-semibold">Composite basemaps and environmental overlays</h2>
              <p className="mt-1 text-xs text-zinc-500">Weather presets include ESRI Street, ESRI Imagery, and the selected near-live overlay.</p>
            </div>
            <div className="flex gap-2">
              <button onClick={checkSources} disabled={busy} className="flex items-center gap-2 rounded-none border border-zinc-300 dark:border-white/15 px-3 py-2 text-xs hover:bg-zinc-100 dark:hover:bg-white/10 disabled:opacity-50">
                <Radio size={13} /> Test sources
              </button>
              <button
                onClick={() => { void load() }}
                disabled={loading || busy}
                className="flex items-center gap-2 rounded-none border border-zinc-300 dark:border-white/15 px-3 py-2 text-xs hover:bg-zinc-100 dark:hover:bg-white/10 disabled:opacity-50"
              >
                <RefreshCw size={13} /> Refresh
              </button>
            </div>
          </div>

          <div className="mt-4 grid gap-2 md:grid-cols-2">
            {presets.map(preset => (
              <label key={preset.id} className="flex cursor-pointer items-start gap-3 rounded-none border border-zinc-200 dark:border-white/10 bg-zinc-50 dark:bg-black/20 p-3 hover:border-accent-ring/60">
                <input
                  type="checkbox"
                  checked={selected.has(preset.id)}
                  onChange={() => toggleEntry(preset.id)}
                  className="mt-0.5 accent-current"
                />
                <span className="min-w-0">
                  <span className="block text-sm font-semibold">{preset.name}</span>
                  <span className="mt-0.5 block text-xs text-zinc-500">{preset.description} · {preset.layer_count} layer{preset.layer_count === 1 ? '' : 's'}</span>
                </span>
              </label>
            ))}
          </div>

          {librarySources.length > 0 && (
            <div className="mt-5 border-t border-zinc-200 dark:border-white/10 pt-4">
              <h3 className="hud-label mb-2 text-xs font-semibold text-zinc-500">Stored XML sources</h3>
              <div className="grid gap-2 md:grid-cols-2">
                {librarySources.map(source => (
                  <div key={source.id} className="flex items-start gap-3 rounded-none border border-zinc-200 dark:border-white/10 p-3 hover:border-accent-ring/60">
                    <input type="checkbox" aria-label={`Select ${source.name}`} checked={selected.has(source.id)} onChange={() => toggleEntry(source.id)} className="mt-0.5 accent-current" />
                    <button type="button" onClick={() => toggleEntry(source.id)} className="min-w-0 flex-1 text-left">
                      <span className="block truncate text-sm font-semibold">{source.name}</span>
                      <span className="block text-xs text-zinc-500">{source.provider} · {source.kind === 'offline' ? 'offline MBTiles' : 'XML source'}</span>
                    </button>
                    {(source.provider === 'Custom' || source.provider === 'Offline') && (
                      <button type="button" onClick={() => { void removeLibrarySource(source) }} disabled={busy} title="Delete stored source" className="rounded-none p-1.5 text-red-500 hover:bg-red-50 dark:hover:bg-red-500/10 disabled:opacity-50"><Trash2 size={13} /></button>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}

          {health.length > 0 && (
            <div className="mt-5 border-t border-zinc-200 dark:border-white/10 pt-4">
              <h3 className="hud-label mb-2 text-xs font-semibold text-zinc-500">Upstream health</h3>
              <div className="flex flex-wrap gap-2">
                {health.map(source => (
                  <span key={source.id} title={source.error} className={`rounded-none px-2 py-1 font-mono text-[10px] ${source.status === 'healthy' ? 'bg-green-100 text-green-700 dark:bg-green-500/10 dark:text-green-400' : 'bg-red-100 text-red-700 dark:bg-red-500/10 dark:text-red-400'}`}>
                    {source.id} · {source.status === 'healthy' ? `${source.latency_ms}ms` : 'failed'}
                  </span>
                ))}
              </div>
            </div>
          )}
        </section>

        <section className="grid gap-4 lg:grid-cols-[1fr_1fr]">
          <div className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 hud-glass p-4">
            <HudCorners />
            <div className="flex items-center gap-2">
              <Radio size={16} className={recipients.length > 0 ? 'text-green-500' : 'text-zinc-500'} />
              <h2 className="text-sm font-semibold">Connected EUDs</h2>
              <span className="ml-auto font-mono text-xs text-zinc-500">{recipients.length} online</span>
            </div>
            {recipientError ? (
              <div className="mt-4 rounded-none border border-yellow-300/60 dark:border-yellow-600/30 bg-yellow-50 dark:bg-yellow-500/[0.05] p-3">
                <p className="text-xs text-yellow-800 dark:text-yellow-300">{recipientError}</p>
                <button onClick={setupConnection} disabled={busy} className="mt-3 flex items-center gap-2 rounded-none bg-accent-fill px-3 py-2 text-xs text-accent-text hover:bg-accent-fill-hover disabled:opacity-50">
                  <Radio size={13} /> Set up service certificate
                </button>
              </div>
            ) : recipients.length === 0 ? (
              <p className="mt-4 text-xs text-zinc-500">No clients are currently connected to TAK Server.</p>
            ) : (
              <div className="mt-3 space-y-2">
                <label className="flex cursor-pointer items-center gap-3 rounded-none border border-zinc-200 dark:border-white/10 p-2.5 text-sm font-medium">
                  <input type="checkbox" checked={allRecipients} onChange={() => { setAllRecipients(true); setSelectedRecipients(new Set()) }} />
                  All connected EUDs
                </label>
                {recipientGroups.length > 1 && (
                  <div className="flex flex-wrap gap-1">
                    {recipientGroups.map(group => <button key={group} onClick={() => selectRecipientGroup(group)} className="rounded-none border border-zinc-200 dark:border-white/10 px-2 py-1 text-[10px] hover:bg-zinc-100 dark:hover:bg-white/5">{group}</button>)}
                  </div>
                )}
                <div className="max-h-48 space-y-1 overflow-y-auto pr-1">
                  {recipients.map(recipient => (
                    <label key={recipient.uid} className="flex cursor-pointer items-center gap-3 rounded-none px-2.5 py-2 hover:bg-zinc-100 dark:hover:bg-white/5">
                      <input
                        type="checkbox"
                        checked={allRecipients || selectedRecipients.has(recipient.uid)}
                        onChange={() => toggleRecipient(recipient.uid)}
                      />
                      <span className="text-sm">{recipient.callsign}</span>
                      <span className="ml-auto truncate text-right font-mono text-[10px] text-zinc-500">{recipient.group}<br />{recipient.uid}</span>
                    </label>
                  ))}
                </div>
              </div>
            )}
          </div>

          <div className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 hud-glass p-4">
            <HudCorners />
            <div className="flex items-center gap-2">
              <CloudRain size={16} />
              <h2 className="text-sm font-semibold">Distribution</h2>
            </div>
            <p className="mt-3 text-xs text-zinc-500">TAK Server creates an invite-only mission, adds the selected layers, and sends the archive and invitation to each selected live client UID.</p>
            <dl className="mt-4 grid grid-cols-2 gap-2 text-xs">
              <div className="rounded-none bg-zinc-100 dark:bg-white/5 p-3"><dt className="text-zinc-500">Selected entries</dt><dd className="mt-1 font-mono text-base">{selected.size}</dd></div>
              <div className="rounded-none bg-zinc-100 dark:bg-white/5 p-3"><dt className="text-zinc-500">Recipients</dt><dd className="mt-1 font-mono text-base">{recipientCount}</dd></div>
            </dl>
            <label className="mt-4 block text-xs text-zinc-500">
              Weather overlay opacity <span className="float-right font-mono text-zinc-700 dark:text-zinc-300">{overlayOpacity}%</span>
              <input type="range" min={0} max={100} value={overlayOpacity} onChange={event => setOverlayOpacity(Number(event.target.value))} className="mt-2 w-full accent-current" />
            </label>
            <button
              onClick={pushSelected}
              disabled={busy || selected.size === 0 || recipientCount === 0}
              className="mt-4 flex w-full items-center justify-center gap-2 rounded-none bg-accent-fill px-4 py-2.5 text-sm font-medium text-accent-text hover:bg-accent-fill-hover disabled:opacity-50"
            >
              <Send size={15} /> {busy ? 'Publishing…' : 'Push to Connected EUDs'}
            </button>
          </div>
        </section>

        <section className="grid gap-4 lg:grid-cols-2">
          <form onSubmit={addXmlFile} className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 hud-glass p-4 space-y-3">
            <HudCorners />
            <div className="flex items-center gap-2"><FileUp size={16} /><h2 className="text-sm font-semibold">Add XML File</h2></div>
            <p className="text-xs text-zinc-500">Upload an ATAK/MOBAC customMapSource or customWmsMapSource XML file.</p>
            <input value={fileName} onChange={event => setFileName(event.target.value)} required maxLength={80} placeholder="Basemap name" className="w-full rounded-none border border-zinc-300 dark:border-white/10 bg-zinc-50 dark:bg-black/20 px-3 py-2 text-sm" />
            <input ref={fileRef} type="file" accept=".xml,text/xml,application/xml" required className="w-full rounded-none border border-zinc-300 dark:border-white/10 bg-zinc-50 dark:bg-black/20 px-3 py-2 text-xs" />
            <button disabled={busy} className="flex items-center gap-2 rounded-none bg-accent-fill px-3 py-2 text-sm text-accent-text hover:bg-accent-fill-hover disabled:opacity-50"><Upload size={14} /> Add XML File</button>
          </form>

          <form onSubmit={addXmlUrl} className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 hud-glass p-4 space-y-3">
            <HudCorners />
            <div className="flex items-center gap-2"><CloudRain size={16} /><h2 className="text-sm font-semibold">Add XML URL</h2></div>
            <p className="text-xs text-zinc-500">Import a public HTTPS URL that points directly to an ATAK XML map source.</p>
            <input value={urlName} onChange={event => setUrlName(event.target.value)} required maxLength={80} placeholder="Basemap name" className="w-full rounded-none border border-zinc-300 dark:border-white/10 bg-zinc-50 dark:bg-black/20 px-3 py-2 text-sm" />
            <input value={xmlUrl} onChange={event => setXmlUrl(event.target.value)} required type="url" placeholder="https://example.com/map.xml" className="w-full rounded-none border border-zinc-300 dark:border-white/10 bg-zinc-50 dark:bg-black/20 px-3 py-2 text-sm" />
            <button disabled={busy} className="flex items-center gap-2 rounded-none bg-accent-fill px-3 py-2 text-sm text-accent-text hover:bg-accent-fill-hover disabled:opacity-50"><Upload size={14} /> Add XML URL</button>
          </form>
        </section>

        <section className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 hud-glass p-4">
          <HudCorners />
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-zinc-200 dark:border-white/10 pb-3">
            <div className="flex items-center gap-2"><History size={16} /><h2 className="text-sm font-semibold">Distribution history</h2></div>
            <button onClick={cleanupHistory} disabled={busy} className="rounded-none border border-zinc-300 dark:border-white/15 px-3 py-2 text-xs hover:bg-zinc-100 dark:hover:bg-white/10 disabled:opacity-50">Clean missions older than 30 days</button>
          </div>
          {history.length === 0 ? (
            <p className="py-6 text-center text-xs text-zinc-500">No basemap missions have been sent yet.</p>
          ) : (
            <div className="mt-3 space-y-2">
              {history.map(distribution => (
                <div key={distribution.id} className="flex flex-wrap items-center gap-3 rounded-none border border-zinc-200 dark:border-white/10 p-3">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className={`rounded-none px-1.5 py-0.5 text-[10px] font-bold uppercase ${distribution.status === 'completed' ? 'bg-green-100 text-green-700 dark:bg-green-500/10 dark:text-green-400' : distribution.status === 'failed' ? 'bg-red-100 text-red-700 dark:bg-red-500/10 dark:text-red-400' : 'bg-zinc-200 text-zinc-600 dark:bg-white/10 dark:text-zinc-300'}`}>{distribution.status}</span>
                      <span className="truncate font-mono text-xs">{distribution.mission_name ?? distribution.request_id}</span>
                    </div>
                    <p className="mt-1 text-[11px] text-zinc-500">{distribution.layer_count} layers · {distribution.recipient_count} recipients · {distribution.accepted_count} accepted · {new Date(distribution.created_at).toLocaleString()}</p>
                    {distribution.error && <p className="mt-1 text-xs text-red-500">{distribution.error}</p>}
                  </div>
                  {(distribution.status === 'completed' || distribution.status === 'failed') && (
                    <div className="flex gap-1">
                      {distribution.status === 'completed' && (
                      <button onClick={() => { void refreshDelivery(distribution) }} disabled={busy} title="Refresh acceptance" className="rounded-none p-2 hover:bg-zinc-100 dark:hover:bg-white/10"><RefreshCw size={13} /></button>
                      )}
                      <button onClick={() => { void resend(distribution) }} disabled={busy} title="Resend" className="rounded-none p-2 hover:bg-zinc-100 dark:hover:bg-white/10"><RotateCcw size={13} /></button>
                      <button onClick={() => { void removeDistribution(distribution) }} disabled={busy} title="Delete mission" className="rounded-none p-2 text-red-500 hover:bg-red-50 dark:hover:bg-red-500/10"><Trash2 size={13} /></button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </section>

        <form onSubmit={buildOffline} className="hud-frame relative rounded-none border border-zinc-200 dark:border-white/10 hud-glass p-4 space-y-3">
          <HudCorners />
          <div className="flex items-center gap-2"><CloudRain size={16} /><h2 className="text-sm font-semibold">Build Offline AOI</h2></div>
          <p className="text-xs text-zinc-500">Download a bounded area into MBTiles, then select it above and push it inside the TAK mission package.</p>
          <div className="grid gap-3 md:grid-cols-2">
            <input value={offlineName} onChange={event => setOfflineName(event.target.value)} required maxLength={80} placeholder="Offline map name" className="rounded-none border border-zinc-300 dark:border-white/10 bg-zinc-50 dark:bg-black/20 px-3 py-2 text-sm" />
            <select value={offlineSource} onChange={event => setOfflineSource(event.target.value)} className="rounded-none border border-zinc-300 dark:border-white/10 bg-zinc-50 dark:bg-black/20 px-3 py-2 text-sm">
              {offlineSources.map(source => <option key={source.id} value={source.id}>{source.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
            {(['west', 'south', 'east', 'north'] as const).map(field => (
              <label key={field} className="text-xs capitalize text-zinc-500">{field}<input type="number" step="any" required value={offlineBounds[field]} onChange={event => setOfflineBounds(current => ({ ...current, [field]: event.target.value }))} className="mt-1 w-full rounded-none border border-zinc-300 dark:border-white/10 bg-zinc-50 dark:bg-black/20 px-2 py-2 text-sm text-zinc-900 dark:text-white" /></label>
            ))}
          </div>
          <div className="grid grid-cols-2 gap-2 md:max-w-xs">
            <label className="text-xs text-zinc-500">Min zoom<input type="number" min={0} max={20} required value={offlineZoom.min} onChange={event => setOfflineZoom(current => ({ ...current, min: event.target.value }))} className="mt-1 w-full rounded-none border border-zinc-300 dark:border-white/10 bg-zinc-50 dark:bg-black/20 px-2 py-2 text-sm text-zinc-900 dark:text-white" /></label>
            <label className="text-xs text-zinc-500">Max zoom<input type="number" min={0} max={20} required value={offlineZoom.max} onChange={event => setOfflineZoom(current => ({ ...current, max: event.target.value }))} className="mt-1 w-full rounded-none border border-zinc-300 dark:border-white/10 bg-zinc-50 dark:bg-black/20 px-2 py-2 text-sm text-zinc-900 dark:text-white" /></label>
          </div>
          <button disabled={busy} className="flex items-center gap-2 rounded-none bg-accent-fill px-3 py-2 text-sm text-accent-text hover:bg-accent-fill-hover disabled:opacity-50"><Upload size={14} /> {busy ? 'Building…' : 'Build MBTiles AOI'}</button>
        </form>

        <p className="text-[11px] text-zinc-500">{providerNotice}</p>
      </div>
    </Layout>
  )
}
