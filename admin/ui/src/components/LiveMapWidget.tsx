import { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { apiJson, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { notify } from '@/lib/notify'
import { renderCotSymbol } from '@/lib/cotSymbol'
import { HudCorners } from '@/components/HudCorners'
import { Play, Square, Settings2 } from 'lucide-react'

interface Status {
  service_cert_ready: boolean
  tracking: boolean
  contact_count: number
}

interface Contact {
  uid: string
  type: string
  affiliation: string
  callsign: string
  lat: number
  lon: number
}

const AFFILIATION_COLOR: Record<string, string> = {
  friendly: '#38bdf8',
  hostile: '#ef4444',
  neutral: '#22c55e',
  unknown: '#eab308',
}
const AFFILIATION_LABEL: Record<string, string> = {
  friendly: 'Friendly',
  hostile: 'Hostile',
  neutral: 'Neutral',
  unknown: 'Unknown',
}
const AFFILIATION_ORDER = ['hostile', 'friendly', 'neutral', 'unknown']

function glowIcon(color: string): L.DivIcon {
  return L.divIcon({
    className: 'tak-glow-marker-wrap',
    html: `<span class="tak-glow-marker" style="--glow-color:${color}"><span class="tak-radar-ping" style="--glow-color:${color}"></span><span class="tak-glow-dot"></span></span>`,
    iconSize: [24, 24],
    iconAnchor: [12, 12],
  })
}

// Renders the real MIL-STD-2525C symbol for a CoT type (matches how ATAK
// itself draws the same type — e.g. hostile UAV -> red diamond frame with
// the UAV glyph). Falls back to a plain glow dot for anything milsymbol
// can't resolve (non-atom types, unrecognized function IDs).
function cotIcon(cotType: string, fallbackColor: string): L.DivIcon {
  const symbol = renderCotSymbol(cotType)
  if (!symbol) return glowIcon(fallbackColor)
  return L.divIcon({
    className: 'tak-symbol-marker-wrap',
    html: symbol.svg,
    iconSize: [symbol.width, symbol.height],
    iconAnchor: [symbol.anchorX, symbol.anchorY],
  })
}

interface LiveMapWidgetProps {
  height: string
  showControls?: boolean
  pollMs?: number
}

export function LiveMapWidget({ height, showControls = false, pollMs = 5000 }: LiveMapWidgetProps) {
  const role = useAuth((s) => s.role)
  const [status, setStatus] = useState<Status | null>(null)
  const [busy, setBusy] = useState(false)
  const [contacts, setContacts] = useState<Contact[]>([])
  const mapRef = useRef<HTMLDivElement>(null)
  const mapInstance = useRef<L.Map | null>(null)
  const markersRef = useRef<Map<string, L.Marker>>(new Map())

  async function loadStatus() {
    try {
      setStatus(await apiJson<Status>('/api/live-map/status'))
    } catch (e) {
      notify.error(errorMessage(e))
    }
  }

  async function loadContacts() {
    if (!mapInstance.current) return
    try {
      const { contacts } = await apiJson<{ contacts: Contact[] }>('/api/live-map/contacts')
      setContacts(contacts)
      const seen = new Set<string>()
      for (const c of contacts) {
        seen.add(c.uid)
        const color = AFFILIATION_COLOR[c.affiliation] ?? AFFILIATION_COLOR.unknown
        const icon = cotIcon(c.type, color)
        const popup = `<strong>${c.callsign}</strong><br/>${c.type}<br/><span class="font-mono text-xs">${c.uid}</span>`
        const existing = markersRef.current.get(c.uid)
        if (existing) {
          existing.setLatLng([c.lat, c.lon])
          existing.setIcon(icon)
          existing.setPopupContent(popup)
        } else {
          const marker = L.marker([c.lat, c.lon], { icon }).addTo(mapInstance.current)
          marker.bindPopup(popup)
          markersRef.current.set(c.uid, marker)
        }
      }
      for (const [uid, marker] of markersRef.current) {
        if (!seen.has(uid)) {
          marker.remove()
          markersRef.current.delete(uid)
        }
      }
    } catch (e) {
      notify.error(errorMessage(e))
    }
  }

  useEffect(() => {
    if (!mapRef.current || mapInstance.current) return
    const map = L.map(mapRef.current, { zoomControl: false }).setView([55.17, 23.88], 7) // Lithuania
    L.control.zoom({ position: 'topright' }).addTo(map)
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
      subdomains: 'abcd',
      maxZoom: 19,
      detectRetina: true,
    }).addTo(map)
    mapInstance.current = map
    return () => {
      map.remove()
      mapInstance.current = null
    }
  }, [])

  useEffect(() => {
    loadStatus()
    const statusId = setInterval(loadStatus, pollMs)
    return () => clearInterval(statusId)
  }, [pollMs])

  useEffect(() => {
    if (!status?.tracking) return
    loadContacts()
    const id = setInterval(loadContacts, Math.min(pollMs, 3000))
    return () => clearInterval(id)
  }, [status?.tracking, pollMs])

  async function handleSetup() {
    setBusy(true)
    try {
      await apiJson('/api/replay/setup', { method: 'POST' })
      notify.success('Service certificate ready')
      await loadStatus()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  async function handleStart() {
    setBusy(true)
    try {
      await apiJson('/api/live-map/start', { method: 'POST' })
      notify.success('Live tracking started')
      await loadStatus()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  async function handleStop() {
    setBusy(true)
    try {
      await apiJson('/api/live-map/stop', { method: 'POST' })
      notify.success('Live tracking stopped')
      for (const marker of markersRef.current.values()) marker.remove()
      markersRef.current.clear()
      setContacts([])
      await loadStatus()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  const legendItems = useMemo(() => {
    const counts = new Map<string, number>()
    for (const c of contacts) {
      const key = AFFILIATION_LABEL[c.affiliation] ? c.affiliation : 'unknown'
      counts.set(key, (counts.get(key) ?? 0) + 1)
    }
    return AFFILIATION_ORDER
      .filter((a) => counts.has(a))
      .map((a) => ({ affiliation: a, label: AFFILIATION_LABEL[a], color: AFFILIATION_COLOR[a], count: counts.get(a)! }))
  }, [contacts])

  const statusText = status?.tracking
    ? `${status.contact_count} contact${status.contact_count === 1 ? '' : 's'} tracked`
    : status?.service_cert_ready
      ? 'Tracking stopped'
      : 'Not set up'

  return (
    <div className="hud-frame relative" style={{ height }}>
      <HudCorners />
      <div className="tak-dark-map relative rounded-md overflow-hidden border border-white/10 w-full h-full">
      <div ref={mapRef} className="w-full h-full" />
      <div className="tak-scanline" />

      <div className="tak-map-glass absolute top-3 left-3 z-[500] rounded-md border border-white/10 px-3 py-2.5 flex items-center gap-3 max-w-[calc(100%-5.5rem)]">
        <span className="relative flex h-2 w-2 shrink-0">
          <span className={`hud-live-dot absolute inline-flex h-full w-full rounded-full ${status?.tracking ? 'bg-accent-fill text-accent-fill' : 'bg-zinc-500 text-zinc-500'}`} />
        </span>
        <span className="text-sm text-zinc-200 truncate">{statusText}</span>
        {showControls && role === 'superadmin' && (
          !status?.service_cert_ready ? (
            <button onClick={handleSetup} disabled={busy}
              className="flex items-center gap-1.5 px-2.5 py-1 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-xs rounded disabled:opacity-50 transition-colors shrink-0">
              <Settings2 size={12} /> Set Up
            </button>
          ) : status.tracking ? (
            <button onClick={handleStop} disabled={busy}
              className="flex items-center gap-1.5 px-2.5 py-1 bg-red-600 hover:bg-red-700 text-white text-xs rounded disabled:opacity-50 transition-colors shrink-0">
              <Square size={12} /> Stop
            </button>
          ) : (
            <button onClick={handleStart} disabled={busy}
              className="flex items-center gap-1.5 px-2.5 py-1 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-xs rounded disabled:opacity-50 transition-colors shrink-0">
              <Play size={12} /> Start
            </button>
          )
        )}
      </div>

      {legendItems.length > 0 && (
        <div className="tak-map-glass absolute bottom-3 left-3 z-[500] rounded-md border border-white/10 px-3 py-2 flex flex-col gap-1.5">
          {legendItems.map((item) => (
            <div key={item.affiliation} className="flex items-center gap-2 text-xs text-zinc-200">
              <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ background: item.color, boxShadow: `0 0 6px ${item.color}` }} />
              <span>{item.label}</span>
              <span className="text-zinc-500 font-mono">{item.count}</span>
            </div>
          ))}
        </div>
      )}
      </div>
    </div>
  )
}
