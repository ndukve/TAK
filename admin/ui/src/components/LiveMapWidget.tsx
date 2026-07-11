import { useEffect, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { HudCorners } from '@/components/HudCorners'
import { apiJson, apiFetch, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { notify } from '@/lib/notify'
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

interface LiveMapWidgetProps {
  height: string
  showControls?: boolean
  pollMs?: number
}

export function LiveMapWidget({ height, showControls = false, pollMs = 5000 }: LiveMapWidgetProps) {
  const role = useAuth((s) => s.role)
  const [status, setStatus] = useState<Status | null>(null)
  const [busy, setBusy] = useState(false)
  const mapRef = useRef<HTMLDivElement>(null)
  const mapInstance = useRef<L.Map | null>(null)
  const markersRef = useRef<Map<string, L.CircleMarker>>(new Map())

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
      const seen = new Set<string>()
      for (const c of contacts) {
        seen.add(c.uid)
        const color = AFFILIATION_COLOR[c.affiliation] ?? AFFILIATION_COLOR.unknown
        const popup = `<strong>${c.callsign}</strong><br/>${c.type}<br/><span class="font-mono text-xs">${c.uid}</span>`
        const existing = markersRef.current.get(c.uid)
        if (existing) {
          existing.setLatLng([c.lat, c.lon])
          existing.setStyle({ color, fillColor: color })
          existing.setPopupContent(popup)
        } else {
          const marker = L.circleMarker([c.lat, c.lon], {
            radius: 7, color, fillColor: color, fillOpacity: 0.8, weight: 2,
          }).addTo(mapInstance.current)
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
    const map = L.map(mapRef.current).setView([55.17, 23.88], 7) // Lithuania
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
      maxZoom: 19,
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
      const res = await apiFetch('/api/replay/setup', { method: 'POST' })
      if (!res.ok) throw new Error((await res.json()).detail ?? 'Setup failed')
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
      const res = await apiFetch('/api/live-map/start', { method: 'POST' })
      if (!res.ok) throw new Error((await res.json()).detail ?? 'Failed to start')
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
      await apiFetch('/api/live-map/stop', { method: 'POST' })
      notify.success('Live tracking stopped')
      for (const marker of markersRef.current.values()) marker.remove()
      markersRef.current.clear()
      await loadStatus()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  const statusText = status?.tracking
    ? `${status.contact_count} contact${status.contact_count === 1 ? '' : 's'}`
    : status?.service_cert_ready
      ? 'Tracking is stopped.'
      : 'Live tracking is not set up yet.'

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <p className="text-sm text-zinc-500">{statusText}</p>
        {showControls && role === 'superadmin' && (
          !status?.service_cert_ready ? (
            <button onClick={handleSetup} disabled={busy}
              className="flex items-center gap-2 px-3 py-1.5 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm rounded-md disabled:opacity-50 transition-colors">
              <Settings2 size={14} /> Set Up
            </button>
          ) : status.tracking ? (
            <button onClick={handleStop} disabled={busy}
              className="flex items-center gap-2 px-3 py-1.5 bg-red-600 hover:bg-red-700 text-white text-sm rounded-md disabled:opacity-50 transition-colors">
              <Square size={14} /> Stop
            </button>
          ) : (
            <button onClick={handleStart} disabled={busy}
              className="flex items-center gap-2 px-3 py-1.5 bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm rounded-md disabled:opacity-50 transition-colors">
              <Play size={14} /> Start Tracking
            </button>
          )
        )}
      </div>
      <div className="hud-frame rounded-md overflow-hidden border border-zinc-200 dark:border-white/10" style={{ height }}>
        <HudCorners />
        <div ref={mapRef} className="w-full h-full" />
      </div>
    </div>
  )
}
