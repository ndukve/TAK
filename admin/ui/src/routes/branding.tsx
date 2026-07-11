import { createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiFetch, apiJson, errorMessage } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { useBranding } from '@/store/branding'
import { notify } from '@/lib/notify'

export const Route = createFileRoute('/branding')({
  beforeLoad: () => {
    const { token, role } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
    if (role !== 'superadmin') throw redirect({ to: '/' })
  },
  component: BrandingPage,
})

interface BrandingResponse {
  org_name: string
  accent_fill: string
  accent_fill_hover: string
  accent_text: string
  accent_ring: string
  logo_url: string | null
}

function BrandingPage() {
  const [orgName, setOrgName] = useState('')
  const [accentFill, setAccentFill] = useState('#2dd4bf')
  const [accentFillHover, setAccentFillHover] = useState('#5eead4')
  const [accentText, setAccentText] = useState('#052e2b')
  const [accentRing, setAccentRing] = useState('#2dd4bf')
  const [logoUrl, setLogoUrl] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const fetchBranding = useBranding((s) => s.fetchBranding)

  async function load() {
    try {
      const data = await apiJson<BrandingResponse>('/api/branding')
      setOrgName(data.org_name)
      setAccentFill(data.accent_fill)
      setAccentFillHover(data.accent_fill_hover)
      setAccentText(data.accent_text)
      setAccentRing(data.accent_ring)
      setLogoUrl(data.logo_url)
    } catch (e) {
      notify.error(errorMessage(e))
    }
  }

  useEffect(() => { load() }, [])

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await apiJson('/api/branding', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          org_name: orgName,
          accent_fill: accentFill,
          accent_fill_hover: accentFillHover,
          accent_text: accentText,
          accent_ring: accentRing,
        }),
      })
      notify.success('Branding updated')
      await fetchBranding()
    } catch (e) {
      notify.error(errorMessage(e))
    } finally {
      setSaving(false)
    }
  }

  async function handleLogoUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    const formData = new FormData()
    formData.append('file', file)
    try {
      const res = await apiFetch('/api/branding/logo', { method: 'POST', body: formData })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      const data: BrandingResponse = await res.json()
      setLogoUrl(data.logo_url)
      notify.success('Logo uploaded')
      await fetchBranding()
    } catch (err) {
      notify.error(errorMessage(err))
    }
  }

  async function handleLogoRemove() {
    try {
      const res = await apiFetch('/api/branding/logo', { method: 'DELETE' })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      setLogoUrl(null)
      notify.success('Logo removed')
      await fetchBranding()
    } catch (err) {
      notify.error(errorMessage(err))
    }
  }

  return (
    <Layout>
      <div className="p-6 max-w-lg">
        <h1 className="text-xl font-semibold mb-6">Branding</h1>
        <form onSubmit={handleSave} className="space-y-4">
          <div className="space-y-1">
            <label className="text-sm text-zinc-700 dark:text-zinc-300">Organization name</label>
            <input type="text" value={orgName} onChange={e => setOrgName(e.target.value)}
              maxLength={64} required
              className="w-full px-3 py-2 rounded-md bg-zinc-200 dark:bg-[#1a1a1d] border border-zinc-300 dark:border-white/10 text-zinc-900 dark:text-white text-sm focus:outline-none focus:ring-2 focus:ring-accent-ring" />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <label className="text-sm text-zinc-700 dark:text-zinc-300">Accent fill</label>
              <div className="flex items-center gap-2">
                <input type="color" value={accentFill} onChange={e => setAccentFill(e.target.value)}
                  className="w-10 h-9 rounded border border-zinc-300 dark:border-white/10 bg-zinc-200 dark:bg-[#1a1a1d]" />
                <span className="text-xs text-zinc-500 font-mono">{accentFill}</span>
              </div>
            </div>
            <div className="space-y-1">
              <label className="text-sm text-zinc-700 dark:text-zinc-300">Accent fill (hover)</label>
              <div className="flex items-center gap-2">
                <input type="color" value={accentFillHover} onChange={e => setAccentFillHover(e.target.value)}
                  className="w-10 h-9 rounded border border-zinc-300 dark:border-white/10 bg-zinc-200 dark:bg-[#1a1a1d]" />
                <span className="text-xs text-zinc-500 font-mono">{accentFillHover}</span>
              </div>
            </div>
            <div className="space-y-1">
              <label className="text-sm text-zinc-700 dark:text-zinc-300">Accent text</label>
              <div className="flex items-center gap-2">
                <input type="color" value={accentText} onChange={e => setAccentText(e.target.value)}
                  className="w-10 h-9 rounded border border-zinc-300 dark:border-white/10 bg-zinc-200 dark:bg-[#1a1a1d]" />
                <span className="text-xs text-zinc-500 font-mono">{accentText}</span>
              </div>
            </div>
            <div className="space-y-1">
              <label className="text-sm text-zinc-700 dark:text-zinc-300">Accent ring</label>
              <div className="flex items-center gap-2">
                <input type="color" value={accentRing} onChange={e => setAccentRing(e.target.value)}
                  className="w-10 h-9 rounded border border-zinc-300 dark:border-white/10 bg-zinc-200 dark:bg-[#1a1a1d]" />
                <span className="text-xs text-zinc-500 font-mono">{accentRing}</span>
              </div>
            </div>
          </div>

          <div className="space-y-1">
            <span className="text-sm text-zinc-700 dark:text-zinc-300">Preview</span>
            <div>
              <button type="button" disabled
                className="px-4 py-2 rounded-md text-sm font-medium"
                style={{ backgroundColor: accentFill, color: accentText }}>
                Sample button
              </button>
            </div>
          </div>

          <button type="submit" disabled={saving}
            className="px-4 py-2 rounded-md bg-accent-fill hover:bg-accent-fill-hover text-accent-text text-sm disabled:opacity-50">
            {saving ? 'Saving…' : 'Save'}
          </button>
        </form>

        <div className="mt-8 pt-6 border-t border-zinc-200 dark:border-white/10 space-y-2">
          <span className="text-sm text-zinc-700 dark:text-zinc-300">Logo</span>
          {logoUrl ? (
            <div className="flex items-center gap-3">
              <img src={logoUrl} alt="Current logo" className="w-16 h-16 rounded border border-zinc-300 dark:border-white/10 object-contain bg-zinc-200 dark:bg-[#1a1a1d]" />
              <button onClick={handleLogoRemove} className="px-3 py-1.5 rounded bg-zinc-300 dark:bg-[#232326] hover:bg-zinc-400 dark:hover:bg-[#2b2b2f] text-sm">Remove</button>
            </div>
          ) : (
            <p className="text-sm text-zinc-500">No logo uploaded.</p>
          )}
          <input type="file" accept=".png,.jpg,.jpeg" onChange={handleLogoUpload}
            className="text-sm text-zinc-600 dark:text-zinc-400 file:mr-3 file:px-3 file:py-1.5 file:rounded file:border-0 file:bg-zinc-300 dark:file:bg-[#232326] file:text-zinc-900 dark:file:text-white file:text-sm hover:file:bg-zinc-400 dark:hover:file:bg-[#2b2b2f]" />
        </div>
      </div>
    </Layout>
  )
}
