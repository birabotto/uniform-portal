import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { Button } from '../components/ui'

const links = [
  { to: '/admin', label: 'Dashboard', end: true },
  { to: '/admin/requests', label: 'Requests' },
  { to: '/admin/inventory', label: 'Inventory' },
  { to: '/admin/employees', label: 'Employees' },
  { to: '/admin/size-chart', label: 'Size chart' },
]

const titles = {
  '/admin': 'Dashboard',
  '/admin/requests': 'Requests',
  '/admin/inventory': 'Inventory',
  '/admin/employees': 'Employees',
  '/admin/size-chart': 'Size chart',
}

export default function AdminLayout() {
  const { signOut, profile, user } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()

  async function handleSignOut() {
    await signOut()
    navigate('/admin/login')
  }

  return (
    <div className="min-h-screen bg-[#edf2f6] p-4 md:p-6">
      <div className="mx-auto grid max-w-[1520px] gap-6 xl:grid-cols-[250px_minmax(0,1fr)]">
        <aside className="rounded-[30px] border border-[#dce4ef] bg-white p-4 shadow-soft xl:sticky xl:top-4 xl:h-[calc(100vh-2rem)]">
          <div className="rounded-[28px] bg-[#2458a8] px-5 py-6 text-white">
            <p className="text-xs font-extrabold uppercase tracking-[0.28em] text-ikeaYellow">IKEA Uniform Portal</p>
            <h2 className="mt-4 text-[2rem] font-extrabold leading-tight">Admin console</h2>
            <p className="mt-4 text-base leading-8 text-blue-50">Manage stock, requests, admins, and request workflow in one place.</p>
          </div>

          <nav className="mt-5 space-y-2">
            {links.map((link) => (
              <NavLink
                key={link.to}
                to={link.to}
                end={link.end}
                className={({ isActive }) =>
                  `flex items-center justify-between rounded-[18px] px-4 py-3 text-[1.05rem] font-bold transition ${
                    isActive ? 'bg-ikeaYellow text-slate-900' : 'text-slate-600 hover:bg-[#f5f8fc] hover:text-slate-900'
                  }`
                }
              >
                {({ isActive }) => (
                  <>
                    <span>{link.label}</span>
                    {isActive ? <span className="text-base">•</span> : null}
                  </>
                )}
              </NavLink>
            ))}
          </nav>
        </aside>

        <main className="space-y-6">
          <div className="flex flex-col gap-4 rounded-[30px] border border-[#dce4ef] bg-white px-6 py-5 shadow-soft md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-ikeaBlue">Dashboard workspace</p>
              <h1 className="mt-2 text-[2rem] font-extrabold text-slate-900">{titles[location.pathname] || 'Dashboard'}</h1>
            </div>

            <div className="flex flex-col gap-3 md:flex-row md:items-center">
              <div className="text-left md:text-right">
                <p className="text-lg font-bold text-slate-900">{profile?.full_name ?? user?.email}</p>
                <p className="text-sm text-slate-500">{profile?.email ?? user?.email}</p>
              </div>
              <Button variant="ghost" className="h-[48px] min-w-[110px] rounded-[18px] border border-[#d7dfe8] bg-white" onClick={handleSignOut}>Sign out</Button>
            </div>
          </div>

          <Outlet />
        </main>
      </div>
    </div>
  )
}
