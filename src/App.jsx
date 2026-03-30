import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './contexts/AuthContext'
import AdminLayout from './layouts/AdminLayout'
import AdminDashboardPage from './pages/AdminDashboardPage'
import AdminEmployeesPage from './pages/AdminEmployeesPage'
import AdminInventoryPage from './pages/AdminInventoryPage'
import AdminLoginPage from './pages/AdminLoginPage'
import AdminRequestsPage from './pages/AdminRequestsPage'
import AdminUsersPage from './pages/AdminUsersPage'
import PublicRequestPage from './pages/PublicRequestPage'

function AccessState({ tone = 'neutral', title, description, action }) {
  const toneClass =
    tone === 'danger'
      ? 'border-red-200 bg-red-50 text-red-700'
      : 'border-slate-200 bg-white text-slate-700'

  return (
    <div className="flex min-h-screen items-center justify-center px-4 py-8">
      <div className={`w-full max-w-xl rounded-[32px] border p-8 shadow-soft ${toneClass}`}>
        <h1 className="text-2xl font-bold text-ink">{title}</h1>
        <p className="mt-3 text-sm leading-6">{description}</p>
        {action ? <div className="mt-6">{action}</div> : null}
      </div>
    </div>
  )
}

function ProtectedRoute({ children }) {
  const { user, loading, configError, signOut } = useAuth()

  if (loading) {
    return <div className="flex min-h-screen items-center justify-center text-slate-600">Loading dashboard...</div>
  }

  if (configError) {
    return <AccessState tone="danger" title="Supabase is not configured" description={configError} />
  }

  if (!user) {
    return <Navigate to="/admin/login" replace />
  }

  return children
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/request" replace />} />
      <Route path="/request" element={<PublicRequestPage />} />
      <Route path="/admin/login" element={<AdminLoginPage />} />
      <Route
        path="/admin"
        element={
          <ProtectedRoute>
            <AdminLayout />
          </ProtectedRoute>
        }
      >
        <Route index element={<AdminDashboardPage />} />
        <Route path="inventory" element={<AdminInventoryPage />} />
        <Route path="requests" element={<AdminRequestsPage />} />
        <Route path="employees" element={<AdminEmployeesPage />} />
        <Route path="admins" element={<AdminUsersPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/request" replace />} />
    </Routes>
  )
}
