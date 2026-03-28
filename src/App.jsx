import { Navigate, Outlet, Route, Routes } from 'react-router-dom'
import { useAuth } from './contexts/AuthContext'
import AdminLayout from './layouts/AdminLayout'
import AdminDashboardPage from './pages/AdminDashboardPage'
import AdminEmployeesPage from './pages/AdminEmployeesPage'
import AdminInventoryPage from './pages/AdminInventoryPage'
import AdminLoginPage from './pages/AdminLoginPage'
import AdminRequestsPage from './pages/AdminRequestsPage'
import AdminSizeChartPage from './pages/AdminSizeChartPage'
import PublicRequestPage from './pages/PublicRequestPage'

function CenteredMessage({ children }) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-softBg px-4">
      <div className="w-full max-w-md rounded-3xl border border-softBorder bg-white p-8 text-center shadow-soft">
        {children}
      </div>
    </div>
  )
}

function ProtectedRoute() {
  const { user, loading, configError } = useAuth()

  if (loading) {
    return <CenteredMessage><p className="text-lg font-semibold text-slate-700">Loading...</p></CenteredMessage>
  }

  if (configError) {
    return (
      <CenteredMessage>
        <p className="text-lg font-semibold text-red-600">Supabase is not configured.</p>
        <p className="mt-3 text-sm text-slate-600">{configError}</p>
      </CenteredMessage>
    )
  }

  if (!user) {
    return <Navigate to="/admin/login" replace />
  }

  return <Outlet />
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/request" replace />} />
      <Route path="/request" element={<PublicRequestPage />} />
      <Route path="/admin/login" element={<AdminLoginPage />} />

      <Route element={<ProtectedRoute />}>
        <Route path="/admin" element={<AdminLayout />}>
          <Route index element={<AdminDashboardPage />} />
          <Route path="requests" element={<AdminRequestsPage />} />
          <Route path="inventory" element={<AdminInventoryPage />} />
          <Route path="employees" element={<AdminEmployeesPage />} />
          <Route path="size-chart" element={<AdminSizeChartPage />} />
        </Route>
      </Route>
    </Routes>
  )
}
