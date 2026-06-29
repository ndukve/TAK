import { Link, useNavigate, useRouterState } from '@tanstack/react-router'
import { useAuth } from '@/store/auth'
import { cn } from '@/lib/utils'
import { apiFetch } from '@/lib/api'
import {
  LayoutDashboard, Users, Package, Puzzle, Map,
  ScrollText, Terminal, ShieldUser, LogOut
} from 'lucide-react'

const navItems = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/users', label: 'Users', icon: Users },
  { to: '/packages', label: 'Packages', icon: Package },
  { to: '/plugins', label: 'Plugins', icon: Puzzle },
  { to: '/maps', label: 'Maps', icon: Map },
  { to: '/logs', label: 'Logs', icon: ScrollText },
]

const superAdminItems = [
  { to: '/shell', label: 'Shell', icon: Terminal },
  { to: '/admin-users', label: 'Admin Users', icon: ShieldUser },
]

export function Layout({ children }: { children: React.ReactNode }) {
  const { role, clear } = useAuth()
  const navigate = useNavigate()
  const routerState = useRouterState()
  const current = routerState.location.pathname

  async function handleLogout() {
    await apiFetch('/auth/logout', { method: 'POST' })
    clear()
    navigate({ to: '/login' })
  }

  const items = role === 'superadmin' ? [...navItems, ...superAdminItems] : navItems

  return (
    <div className="flex h-screen bg-zinc-950 text-zinc-100">
      <aside className="w-56 flex-shrink-0 border-r border-zinc-800 flex flex-col">
        <div className="p-4 border-b border-zinc-800">
          <span className="font-bold text-lg tracking-tight">TAK Admin</span>
        </div>
        <nav className="flex-1 p-2 space-y-1">
          {items.map(({ to, label, icon: Icon }) => (
            <Link
              key={to}
              to={to}
              className={cn(
                'flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors',
                current === to
                  ? 'bg-zinc-800 text-white'
                  : 'text-zinc-400 hover:text-white hover:bg-zinc-800/50'
              )}
            >
              <Icon size={16} />
              {label}
            </Link>
          ))}
        </nav>
        <div className="p-2 border-t border-zinc-800">
          <button
            onClick={handleLogout}
            className="flex items-center gap-3 w-full px-3 py-2 rounded-md text-sm text-zinc-400 hover:text-white hover:bg-zinc-800/50 transition-colors"
          >
            <LogOut size={16} />
            Sign out
          </button>
        </div>
      </aside>
      <main className="flex-1 overflow-auto">{children}</main>
    </div>
  )
}
