import { createFileRoute, useNavigate } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { useAuth } from '@/store/auth'
import { errorMessage } from '@/lib/api'
import { useBranding } from '@/store/branding'
import { notify } from '@/lib/notify'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { PasswordInput } from '@/components/PasswordInput'

export const Route = createFileRoute('/login')({
  component: LoginPage,
})

function LoginPage() {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const { setToken } = useAuth()
  const navigate = useNavigate()
  const orgName = useBranding((s) => s.orgName)
  const logoUrl = useBranding((s) => s.logoUrl)
  const [oidc, setOidc] = useState<{ enabled: boolean; provider_name: string } | null>(null)

  useEffect(() => {
    fetch('/auth/oidc/config', { credentials: 'include' })
      .then((r) => (r.ok ? r.json() : null))
      .then(setOidc)
      .catch(() => {})
  }, [])

  useEffect(() => {
    const error = new URLSearchParams(window.location.search).get('error')
    if (!error) return
    notify.error(error === 'oidc_account'
      ? 'SSO account access was rejected. Contact an administrator.'
      : 'SSO sign-in failed. Please try again.')
    window.history.replaceState({}, '', '/login')
  }, [])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const res = await fetch('/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ username, password }),
      })
      if (!res.ok) {
        const err = await res.json()
        throw new Error(err.detail ?? 'Login failed')
      }
      const { access_token } = await res.json()
      const payload = JSON.parse(atob(access_token.split('.')[1]))
      setToken(access_token, payload.role, payload.username, payload.auth_provider)
      navigate({ to: '/' })
    } catch (err) {
      notify.error(errorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background hud-grid-bg">
      <Card className="w-full max-w-sm space-y-6 p-8">
        <div className="flex flex-col items-center text-center">
          {logoUrl && <img src={logoUrl} alt="" className="w-20 h-20 object-contain mb-4" />}
          <h1 className="font-display text-3xl tracking-tight text-foreground">{orgName}</h1>
          <p className="scout-label mt-2">Sign in to manage your TAK server</p>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          <Input
            label="Username"
            type="text"
            value={username}
            onChange={e => setUsername(e.target.value)}
            required
          />
          <div className="flex flex-col gap-1.5">
            <Label>Password</Label>
            <PasswordInput
              value={password}
              onChange={e => setPassword(e.target.value)}
              required
              className="h-9 w-full min-w-0 border bg-surface-inset px-3 pr-10 font-sans text-sm text-foreground transition-[border-color,box-shadow] duration-120 ease-standard outline-none placeholder:text-subtle focus-visible:border-primary focus-visible:ring-3 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50"
            />
          </div>
          <Button type="submit" disabled={loading} className="w-full uppercase tracking-wider">
            {loading ? 'Signing in…' : 'Sign in'}
          </Button>
        </form>
        {oidc?.enabled && (
          <>
            <div className="flex items-center gap-3">
              <div className="flex-1 h-px bg-border" />
              <span className="scout-label text-[10px]">or</span>
              <div className="flex-1 h-px bg-border" />
            </div>
            <Button render={<a href="/auth/oidc/login" />} variant="outline" className="w-full">
              Sign in with {oidc.provider_name}
            </Button>
          </>
        )}
      </Card>
    </div>
  )
}
