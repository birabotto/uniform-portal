import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

const links = [
  { to: '/admin', label: 'Dashboard', end: true },
  { to: '/admin/requests', label: 'Requests' },
  { to: '/admin/inventory', label: 'Inventory' },
  { to: '/admin/employees', label: 'Employees' },
  { to: '/admin/admins', label: 'Users' },
]

export default function AdminLayout() {
  const { signOut, profile, user } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()

  async function handleSignOut() {
    await signOut()
    navigate('/admin/login')
  }

  return (
    <div className="min-h-screen bg-transparent">
      <div className="mx-auto grid min-h-screen max-w-[1600px] gap-6 px-4 py-4 lg:grid-cols-[280px_minmax(0,1fr)] lg:px-6">
        <aside className="glass hidden p-4 lg:flex lg:flex-col">
          <div className="rounded-[24px] bg-[#0058A3] p-5 text-white">
            <div className="text-xs font-bold uppercase tracking-[0.24em] text-[#FFDA1A]">IKEA Uniform Portal</div>
            <h1 className="mt-3 text-2xl font-bold">Admin console</h1>
            <p className="mt-2 text-sm text-blue-100">Manage employees, stock, requests, analytics, and dashboard users in one place.</p>
          </div>

          <nav className="mt-5 space-y-2">
            {links.map((link) => (
              <NavLink
                key={link.to}
                to={link.to}
                end={link.end}
                className={({ isActive }) =>
                  `flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold transition ${
                    isActive
                      ? 'bg-[#FFDA1A] text-slate-900 shadow-soft'
                      : 'text-slate-600 hover:bg-white hover:text-slate-900'
                  }`
                }
              >
                <span>{link.label}</span>
                {location.pathname === link.to ? <span>•</span> : null}
              </NavLink>
            ))}
          </nav>

          <div className="mt-auto rounded-[24px] border border-slate-200 bg-white p-4">
            <div className="text-sm font-semibold text-ink">Signed in as</div>
            <div className="mt-3 text-base font-semibold text-ink">{profile?.full_name ?? user?.email}</div>
            <div className="text-sm text-slate-500">{profile?.email ?? user?.email}</div>
            <div className="mt-2 inline-flex rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-slate-600">
              Dashboard user
            </div>
            <button className="btn-secondary mt-4 w-full" onClick={handleSignOut}>Sign out</button>
          </div>
        </aside>

        <div className="space-y-6">
          <header className="glass sticky top-3 z-20 p-4 lg:p-5">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <div className="text-xs font-bold uppercase tracking-[0.24em] text-ikeaBlue">Dashboard workspace</div>
                <div className="mt-1 text-xl font-bold text-ink">{links.find((item) => item.to === location.pathname)?.label ?? 'Admin dashboard'}</div>
              </div>
              <div className="flex flex-wrap gap-2 lg:hidden">
                {links.map((link) => (
                  <NavLink
                    key={link.to}
                    to={link.to}
                    end={link.end}
                    className={({ isActive }) =>
                      `rounded-full px-4 py-2 text-sm font-semibold transition ${
                        isActive ? 'bg-ikeaBlue text-white' : 'bg-white text-slate-600'
                      }`
                    }
                  >
                    {link.label}
                  </NavLink>
                ))}
              </div>
              <div className="hidden items-center gap-3 lg:flex">
                <div className="text-right text-sm">
                  <div className="font-semibold text-ink">{profile?.full_name ?? user?.email}</div>
                  <div className="text-slate-500">{profile?.email ?? user?.email}</div>
                </div>
                <button className="btn-secondary" onClick={handleSignOut}>Sign out</button>
              </div>
            </div>
          </header>

          <main>
            <Outlet />
          </main>
        </div>
      </div>
    </div>
  )
}
