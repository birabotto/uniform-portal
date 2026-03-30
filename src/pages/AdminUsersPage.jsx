import { useEffect, useMemo, useState } from 'react'
import Badge from '../components/Badge'
import PageHeader from '../components/PageHeader'
import { createAdminUser, listDashboardUsers } from '../lib/adminApi'

const initialForm = {
  full_name: '',
  email: '',
  password: '',
}

export default function AdminUsersPage() {
  const [form, setForm] = useState(initialForm)
  const [message, setMessage] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [users, setUsers] = useState([])
  const [loadingUsers, setLoadingUsers] = useState(true)
  const [search, setSearch] = useState('')

  async function loadUsers() {
    setLoadingUsers(true)
    setMessage('')

    try {
      const result = await listDashboardUsers()
      setUsers(result.users ?? [])
    } catch (error) {
      setMessage(error.message)
    } finally {
      setLoadingUsers(false)
    }
  }

  useEffect(() => {
    loadUsers()
  }, [])

  async function handleSubmit(event) {
    event.preventDefault()
    setSubmitting(true)
    setMessage('')

    try {
      const result = await createAdminUser(form)
      setMessage(`Dashboard user created successfully: ${result.user.email}`)
      setForm(initialForm)
      await loadUsers()
    } catch (error) {
      setMessage(error.message)
    } finally {
      setSubmitting(false)
    }
  }

  const filteredUsers = useMemo(() => {
    const term = search.trim().toLowerCase()
    return users.filter((user) => {
      if (!term) return true
      return `${user.full_name} ${user.email} ${user.status}`.toLowerCase().includes(term)
    })
  }, [users, search])

  const confirmedCount = users.filter((item) => item.confirmed_at).length

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Access"
        title="Manage dashboard users"
        description="Create Supabase Auth users directly from the dashboard and review everyone who can access /admin. No profiles table is required."
      />

      <div className="grid gap-6 xl:grid-cols-[minmax(0,0.95fr)_minmax(320px,1.05fr)]">
        <div className="space-y-6">
          <div className="card p-6">
            <div className="flex items-center justify-between gap-3">
              <div>
                <h2 className="text-xl font-semibold text-ink">Create dashboard user</h2>
                <p className="mt-2 text-sm text-slate-500">Creates a new user in Supabase Authentication. Any authenticated user can open the dashboard.</p>
              </div>
              <Badge tone="approved">{confirmedCount} confirmed</Badge>
            </div>

            {message ? <div className="mt-4 rounded-2xl bg-slate-50 p-4 text-sm text-slate-700">{message}</div> : null}

            <form className="mt-6 space-y-4" onSubmit={handleSubmit}>
              <div>
                <label className="field-label">Full name</label>
                <input
                  className="field"
                  value={form.full_name}
                  onChange={(e) => setForm((current) => ({ ...current, full_name: e.target.value }))}
                  required
                />
              </div>
              <div>
                <label className="field-label">Email</label>
                <input
                  className="field"
                  type="email"
                  value={form.email}
                  onChange={(e) => setForm((current) => ({ ...current, email: e.target.value }))}
                  required
                />
              </div>
              <div>
                <label className="field-label">Temporary password</label>
                <input
                  className="field"
                  type="password"
                  value={form.password}
                  onChange={(e) => setForm((current) => ({ ...current, password: e.target.value }))}
                  placeholder="At least 6 characters"
                  minLength={6}
                  required
                />
              </div>
              <button className="btn-primary w-full" type="submit" disabled={submitting}>
                {submitting ? 'Creating user...' : 'Create user'}
              </button>
            </form>
          </div>

          <div className="card p-6">
            <h2 className="text-xl font-semibold text-ink">Netlify env required</h2>
            <div className="mt-4 rounded-[24px] bg-slate-50 p-4 text-sm text-slate-600">
              Add <strong>SUPABASE_SERVICE_ROLE_KEY</strong> and <strong>VITE_SUPABASE_URL</strong> in Netlify so the server functions can create and list Auth users securely.
            </div>
          </div>
        </div>

        <div className="card p-6">
          <div className="flex items-center justify-between gap-3">
            <h2 className="text-xl font-semibold text-ink">Current dashboard users</h2>
            <input
              className="field max-w-60"
              placeholder="Search users"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </div>
          <div className="mt-5 space-y-3">
            {loadingUsers ? <div className="rounded-2xl bg-slate-50 p-4 text-sm text-slate-500">Loading users...</div> : null}
            {!loadingUsers && filteredUsers.map((account) => (
              <div key={account.id} className="rounded-[24px] border border-slate-200 p-4">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <div className="font-semibold text-ink">{account.full_name || account.email}</div>
                    <div className="text-sm text-slate-500">{account.email}</div>
                    <div className="mt-1 text-xs text-slate-400">
                      Created {account.created_at ? new Date(account.created_at).toLocaleString() : '—'}
                    </div>
                  </div>
                  <Badge tone={account.confirmed_at ? 'approved' : 'pending'}>
                    {account.confirmed_at ? 'confirmed' : 'pending confirmation'}
                  </Badge>
                </div>
              </div>
            ))}
            {!loadingUsers && !filteredUsers.length ? <div className="rounded-2xl bg-slate-50 p-4 text-sm text-slate-500">Users will appear here after they are created.</div> : null}
          </div>
        </div>
      </div>
    </div>
  )
}
