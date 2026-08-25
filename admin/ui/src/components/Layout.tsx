import { useEffect, useState } from 'react'
import { Icon } from '@/components/ui/icon'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Link, useNavigate, useRouterState } from '@tanstack/react-router'
import { useAuth } from '@/store/auth'
import { useRoute } from '@/store/route'
import { cn } from '@/lib/utils'
import { apiFetch, errorMessage } from '@/lib/api'
import { notify } from '@/lib/notify'
import { useBranding } from '@/store/branding'
import { useTheme } from '@/store/theme'
import { useNotifications } from '@/store/notifications'
import { PasswordInput } from '@/components/PasswordInput'

const INPUT_CLASS = "h-9 w-full min-w-0 border bg-surface-inset px-3 font-sans text-sm text-foreground transition-[border-color,box-shadow] duration-120 ease-standard outline-none placeholder:text-subtle focus-visible:border-primary focus-visible:ring-3 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50"

// Three-bar icon that morphs into an X on open — plain CSS transitions on
// each bar's rotation/position/opacity, no icon-swap flash.
function HamburgerIcon({ open }: { open: boolean }) {
  return (
    <span className="relative block w-4 h-4">
      <span className={cn(
        'absolute left-0 top-0.5 w-4 h-0.5 rounded-full bg-current transition-all duration-300',
        open && 'top-[7px] rotate-45'
      )} />
      <span className={cn(
        'absolute left-0 top-[7px] w-4 h-0.5 rounded-full bg-current transition-all duration-300',
        open && 'opacity-0'
      )} />
      <span className={cn(
        'absolute left-0 bottom-0.5 w-4 h-0.5 rounded-full bg-current transition-all duration-300',
        open && 'bottom-[7px] -rotate-45'
      )} />
    </span>
  )
}

const navItems = [
  { to: '/', label: 'Dashboard', icon: 'dashboard-line' },
  { to: '/packages', label: 'Packages', icon: 'box-3-line' },
  { to: '/plugins', label: 'Plugins', icon: 'puzzle-line' },
  { to: '/maps', label: 'Maps', icon: 'map-2-line' },
]

// Live Map shows real-time contact positions — admin/superadmin only (backend
// enforces this too), so it's kept out of navItems rather than shown to
// readonly users as a dead link.
const liveMapItem = { to: '/live-map', label: 'Live Map', icon: 'satellite-line' }

const fieldItems = [
  { to: '/packages', label: 'Packages', icon: 'box-3-line' },
  { to: '/plugins', label: 'Plugins', icon: 'puzzle-line' },
  { to: '/maps', label: 'Maps', icon: 'map-2-line' },
]

const superAdminItems = [
  { to: '/basemaps', label: 'Basemaps', icon: 'rainy-line' },
  { to: '/users', label: 'Users', icon: 'group-line' },
  { to: '/admin-users', label: 'Admin Users', icon: 'shield-user-line' },
  { to: '/certificates', label: 'Certificates', icon: 'shield-check-line' },
  { to: '/replay', label: 'Replay', icon: 'rss-line' },
  { to: '/shell', label: 'Shell', icon: 'terminal-line' },
  { to: '/logs', label: 'Logs', icon: 'file-list-3-line' },
  { to: '/audit-log', label: 'Audit Logs', icon: 'history-line' },
]

function passwordStrength(p: string): { score: number; label: string; color: string } {
  let score = 0
  if (p.length >= 12) score++
  if (p.length >= 16) score++
  if (/[A-Z]/.test(p)) score++
  if (/[a-z]/.test(p)) score++
  if (/\d/.test(p)) score++
  if (/[^A-Za-z0-9]/.test(p)) score++
  if (score <= 2) return { score, label: 'Weak', color: 'bg-critical' }
  if (score <= 4) return { score, label: 'Fair', color: 'bg-warning' }
  if (score === 5) return { score, label: 'Good', color: 'bg-primary' }
  return { score, label: 'Strong', color: 'bg-nominal' }
}

function ChangePasswordFields({ onClose, forced }: { onClose: () => void; forced?: boolean }) {
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [confirm, setConfirm] = useState('')
  const [error, setError] = useState('')
  const [ok, setOk] = useState(false)
  const strength = passwordStrength(next)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    if (next !== confirm) { setError('Passwords do not match'); return }
    if (next.length < 12) { setError('New password must be at least 12 characters'); return }
    try {
      const res = await apiFetch('/api/admin-users/me/change-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ current_password: current, new_password: next }),
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      setOk(true)
    } catch (err) {
      setError(errorMessage(err) || 'Failed')
    }
  }

  if (ok) {
    return (
      <div className="space-y-4">
        <p className="text-nominal text-sm">Password changed successfully.</p>
        {!forced && <Button type="button" variant="secondary" onClick={onClose} className="w-full">Close</Button>}
      </div>
    )
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      {forced && (
        <p className="text-xs text-warning mb-1">Your password has expired and must be changed before continuing.</p>
      )}
      <PasswordInput placeholder="Current password" value={current} onChange={e => setCurrent(e.target.value)}
        className={cn(INPUT_CLASS, 'pr-10')} required />
      <div className="space-y-1">
        <PasswordInput placeholder="New password (min 12 chars)" value={next} onChange={e => setNext(e.target.value)}
          className={cn(INPUT_CLASS, 'pr-10')} required />
        {next.length > 0 && (
          <div className="space-y-1">
            <div className="flex gap-1 h-1">
              {[1,2,3,4,5,6].map(i => (
                <div key={i} className={`flex-1 rounded-full ${i <= strength.score ? strength.color : 'bg-neutral-surface'}`} />
              ))}
            </div>
            <p className="text-xs text-muted-foreground">{strength.label} · must have uppercase, lowercase, digit, special char</p>
          </div>
        )}
      </div>
      <PasswordInput placeholder="Confirm new password" value={confirm} onChange={e => setConfirm(e.target.value)}
        className={cn(INPUT_CLASS, 'pr-10')} required />
      {error && <p className="text-critical text-xs">{error}</p>}
      <div className="flex gap-2 pt-1">
        {!forced && <Button type="button" variant="secondary" onClick={onClose} className="flex-1">Cancel</Button>}
        <Button type="submit" className="flex-1">Change</Button>
      </div>
    </form>
  )
}

function ChangePasswordModal({ onClose, forced }: { onClose: () => void; forced?: boolean }) {
  return (
    <div className="fixed inset-0 bg-overlay flex items-center justify-center z-[60]">
      <Card className="w-full max-w-sm">
        <h2 className="font-display text-lg mb-4">Change Password</h2>
        <ChangePasswordFields onClose={onClose} forced={forced} />
      </Card>
    </div>
  )
}

function UserSettingsModal({ onClose }: { onClose: () => void }) {
  const { username: currentUsername, setToken, role, authProvider } = useAuth()
  const [newUsername, setNewUsername] = useState(currentUsername ?? '')
  const [usernamePassword, setUsernamePassword] = useState('')
  const [usernameError, setUsernameError] = useState('')
  const [usernameOk, setUsernameOk] = useState(false)

  async function handleUsernameSubmit(e: React.FormEvent) {
    e.preventDefault()
    setUsernameError('')
    try {
      const res = await apiFetch('/api/admin-users/me/change-username', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ current_password: usernamePassword, new_username: newUsername }),
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail ?? res.statusText)
      }
      const data: { access_token: string } = await res.json()
      setToken(data.access_token, role ?? '', newUsername, authProvider ?? 'local')
      setUsernameOk(true)
      notify.success('Username updated')
    } catch (err) {
      setUsernameError(errorMessage(err) || 'Failed')
    }
  }

  return (
    <div className="fixed inset-0 bg-overlay flex items-center justify-center z-[60]">
      <Card className="w-full max-w-sm space-y-6">
        <div className="flex items-center justify-between">
          <h2 className="font-display text-lg">User Settings</h2>
          <button onClick={onClose} className="text-subtle hover:text-foreground text-sm">Close</button>
        </div>

        <div>
          <h3 className="scout-label mb-2">Change Username</h3>
          {usernameOk ? (
            <p className="text-nominal text-sm">Username changed successfully.</p>
          ) : (
            <form onSubmit={handleUsernameSubmit} className="space-y-3">
              <input type="text" placeholder="New username" value={newUsername} onChange={e => setNewUsername(e.target.value)}
                className={INPUT_CLASS} required />
              <PasswordInput placeholder="Current password" value={usernamePassword} onChange={e => setUsernamePassword(e.target.value)}
                className={cn(INPUT_CLASS, 'pr-10')} required />
              {usernameError && <p className="text-critical text-xs">{usernameError}</p>}
              <Button type="submit" className="w-full">Change Username</Button>
            </form>
          )}
        </div>

        <div className="border-t border-border pt-6">
          <h3 className="scout-label mb-2">Change Password</h3>
          <ChangePasswordFields onClose={onClose} />
        </div>
      </Card>
    </div>
  )
}

export function Layout({ children }: { children: React.ReactNode }) {
  const { role, username, authProvider, clear, passwordExpired, setPasswordExpired } = useAuth()
  const orgName = useBranding((s) => s.orgName)
  const logoUrl = useBranding((s) => s.logoUrl)
  const theme = useTheme((s) => s.theme)
  const toggleTheme = useTheme((s) => s.toggleTheme)
  const navigate = useNavigate()
  const routerState = useRouterState()
  const current = routerState.location.pathname
  const setPathname = useRoute((s) => s.setPathname)
  const [showUserSettings, setShowUserSettings] = useState(false)
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const notifications = useNotifications((s) => s.items)
  const clearNotifications = useNotifications((s) => s.clear)
  const [notifOpen, setNotifOpen] = useState(false)
  const [userMenuOpen, setUserMenuOpen] = useState(false)

  useEffect(() => {
    setPathname(current)
  }, [current, setPathname])

  async function handleLogout() {
    try {
      await apiFetch('/auth/logout', { method: 'POST' })
    } catch (err) {
      notify.error(`Sign out request failed: ${errorMessage(err)}`)
    } finally {
      clear()
      navigate({ to: '/login' })
    }
  }

  const items = role === 'field' ? fieldItems : role === 'readonly' ? navItems : [...navItems, liveMapItem]
  const adminItems = role === 'superadmin'
    ? superAdminItems.filter((item) => authProvider === 'local' || item.to !== '/shell')
    : []

  return (
    <div className="flex h-screen bg-background text-foreground">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:px-3 focus:py-2 focus:bg-primary focus:text-primary-foreground focus:text-sm"
      >
        Skip to content
      </a>
      <header className="fixed top-0 left-0 right-0 z-50 h-14 pl-16 pr-4 flex items-center gap-2 min-w-0 border-b border-border bg-surface/95 backdrop-blur-xl">
        <button
          onClick={() => setSidebarOpen(v => !v)}
          className="fixed top-2.5 left-3 z-50 flex items-center justify-center p-2.5 border border-border bg-surface text-muted-foreground hover:text-foreground transition-colors"
          aria-label="Toggle menu"
          aria-expanded={sidebarOpen}
        >
          <HamburgerIcon open={sidebarOpen} />
        </button>
        {logoUrl && <img src={logoUrl} alt="" className="w-7 h-7 object-contain shrink-0" />}
        <span className="font-display font-bold text-xl tracking-tight truncate">{orgName}</span>
        <div className="relative ml-auto">
          <button
            onClick={() => setNotifOpen((v) => !v)}
            aria-label="Notifications"
            className="p-1.5 hover:bg-neutral-surface text-muted-foreground relative focus:outline-none focus:ring-3 focus:ring-ring"
          >
            <Icon name="notification-3-line" size={16} />
            {notifications.length > 0 && (
              <span className="absolute top-0.5 right-0.5 w-2 h-2 rounded-full bg-critical" />
            )}
          </button>
          {notifOpen && (
            <div className="fixed top-14 left-4 right-4 w-auto md:absolute md:top-full md:left-auto md:right-0 md:mt-2 md:w-72 border border-border bg-surface-raised shadow-lg z-50 max-h-80 overflow-y-auto">
              <div className="flex items-center justify-between px-3 py-2 border-b border-border">
                <span className="scout-label">Notifications</span>
                <button onClick={clearNotifications} className="text-xs text-primary-emphasis hover:underline">Clear all</button>
              </div>
              {notifications.length === 0 ? (
                <p className="px-3 py-4 text-sm text-subtle text-center">No notifications yet</p>
              ) : (
                notifications.map((n) => {
                  const content = (
                    <>
                      <span className={`w-1.5 h-1.5 rounded-full mt-1.5 ${n.type === 'success' ? 'bg-nominal' : 'bg-critical'}`} />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm text-foreground break-words">{n.message}</p>
                        <p className="text-xs text-subtle">{new Date(n.timestamp).toLocaleTimeString()}</p>
                      </div>
                    </>
                  )
                  return role === 'superadmin' ? (
                    <button
                      key={n.id}
                      onClick={() => { setNotifOpen(false); navigate({ to: '/logs' }) }}
                      title="View logs"
                      className="flex items-start gap-2 w-full text-left px-3 py-2 border-b border-border-faint last:border-0 hover:bg-neutral-surface transition-colors"
                    >
                      {content}
                    </button>
                  ) : (
                    <div key={n.id} className="flex items-start gap-2 px-3 py-2 border-b border-border-faint last:border-0">
                      {content}
                    </div>
                  )
                })
              )}
            </div>
          )}
        </div>

        <div className="relative">
          <button
            onClick={() => setUserMenuOpen((v) => !v)}
            aria-label="User menu"
            aria-expanded={userMenuOpen}
            className="w-7 h-7 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-xs font-semibold shrink-0 focus:outline-none focus:ring-3 focus:ring-ring"
          >
            {(username ?? '?').slice(0, 2).toUpperCase()}
          </button>
          {userMenuOpen && (
            <div className="fixed top-14 left-4 right-4 w-auto md:absolute md:top-full md:left-auto md:right-0 md:mt-2 md:w-56 border border-border bg-surface-raised shadow-lg z-50 overflow-hidden">
              <div className="px-3 py-2.5 border-b border-border">
                <p className="text-sm text-foreground truncate">{username}</p>
                <p className="text-xs text-subtle">{role}</p>
              </div>
              <div className="p-1">
                <button
                  onClick={() => { toggleTheme(); setUserMenuOpen(false) }}
                  className="flex items-center gap-3 w-full px-3 py-2 text-sm text-muted-foreground hover:text-foreground hover:bg-neutral-surface transition-colors"
                >
                  {theme === 'dark' ? <Icon name="sun-line" size={16} /> : <Icon name="moon-line" size={16} />}
                  {theme === 'dark' ? 'Light mode' : 'Dark mode'}
                </button>
                {authProvider === 'local' && (
                  <button
                    onClick={() => { setUserMenuOpen(false); setShowUserSettings(true) }}
                    className="flex items-center gap-3 w-full px-3 py-2 text-sm text-muted-foreground hover:text-foreground hover:bg-neutral-surface transition-colors"
                  >
                    <Icon name="group-line" size={16} />
                    Account settings
                  </button>
                )}
                {role === 'superadmin' && (
                  <Link
                    to="/branding"
                    onClick={() => setUserMenuOpen(false)}
                    className="flex items-center gap-3 w-full px-3 py-2 text-sm text-muted-foreground hover:text-foreground hover:bg-neutral-surface transition-colors"
                  >
                    <Icon name="settings-3-line" size={16} />
                    Settings
                  </Link>
                )}
                <button
                  onClick={() => { setUserMenuOpen(false); handleLogout() }}
                  className="flex items-center gap-3 w-full px-3 py-2 text-sm text-muted-foreground hover:text-foreground hover:bg-neutral-surface transition-colors"
                >
                  <Icon name="logout-box-r-line" size={16} />
                  Sign out
                </button>
              </div>
            </div>
          )}
        </div>
      </header>
      {sidebarOpen && (
        <div className="fixed inset-0 top-14 bg-overlay z-30" onClick={() => setSidebarOpen(false)} />
      )}
      <aside className={cn(
        'w-64 flex-shrink-0 border-r border-border flex flex-col',
        'fixed top-14 bottom-0 left-0 z-40 bg-surface/95 shadow-xl backdrop-blur-xl transition-transform duration-300 ease-in-out',
        sidebarOpen ? 'translate-x-0' : '-translate-x-full'
      )}>
        <nav className="flex-1 p-2 space-y-1">
          {items.map(({ to, label, icon }) => (
            <Link
              key={to}
              to={to}
              onClick={() => setSidebarOpen(false)}
              className={cn(
                'flex items-center gap-3 pl-3 pr-3 py-2 text-sm border-l-2 transition-colors',
                current === to
                  ? 'border-primary text-foreground'
                  : 'border-transparent text-muted-foreground hover:text-foreground hover:bg-neutral-surface'
              )}
            >
              <Icon name={icon} size={16} />
              {current === to ? `[ ${label} ]` : label}
            </Link>
          ))}
          {adminItems.length > 0 && (
            <>
              <div className="scout-label pt-3 pb-1 px-3">Admin</div>
              {adminItems.map(({ to, label, icon }) => (
                <Link
                  key={to}
                  to={to}
                  onClick={() => setSidebarOpen(false)}
                  className={cn(
                    'flex items-center gap-3 pl-3 pr-3 py-2 text-sm border-l-2 transition-colors',
                    current === to
                      ? 'border-primary text-foreground'
                      : 'border-transparent text-muted-foreground hover:text-foreground hover:bg-neutral-surface'
                  )}
                >
                  <Icon name={icon} size={16} />
                  {current === to ? `[ ${label} ]` : label}
                </Link>
              ))}
            </>
          )}
        </nav>
        <div className="p-2 border-t border-border">
          <p className="px-3 pt-1 text-[10px] text-subtle text-center">TAK Admin {__APP_VERSION__}</p>
        </div>
      </aside>
      <main id="main-content" tabIndex={-1} className="flex-1 overflow-auto pt-14 isolate hud-grid-bg">{children}</main>
      {showUserSettings && <UserSettingsModal onClose={() => setShowUserSettings(false)} />}
      {authProvider === 'local' && passwordExpired && <ChangePasswordModal forced onClose={() => setPasswordExpired(false)} />}
    </div>
  )
}
