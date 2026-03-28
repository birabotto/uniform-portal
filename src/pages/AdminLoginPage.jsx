import { useState } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { Button, Input } from '../components/ui'

export default function AdminLoginPage() {
  const navigate = useNavigate()
  const { signIn, user, configError } = useAuth()
  const [form, setForm] = useState({ email: '', password: '' })
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  if (user) {
    return <Navigate to="/admin" replace />
  }

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    setSubmitting(true)

    const { error: signInError } = await signIn(form.email, form.password)
    if (signInError) {
      setError(signInError.message || 'Unable to sign in.')
      setSubmitting(false)
      return
    }

    navigate('/admin')
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-softBg px-4">
      <div className="grid w-full max-w-5xl overflow-hidden rounded-[32px] border border-softBorder bg-white shadow-soft lg:grid-cols-[1.2fr_0.8fr]">
        <div className="bg-ikeaBlue p-8 text-white md:p-12">
          <p className="text-xs font-bold uppercase tracking-[0.35em] text-ikeaYellow">IKEA Uniform Portal</p>
          <h1 className="mt-5 text-4xl font-bold leading-tight">Admin access for stock, history, employees, and analytics.</h1>
          <p className="mt-5 max-w-lg text-sm text-blue-100">
            This version includes a centralized employee directory, auto-fill by employee ID, full request history, size chart support, and dashboard analytics.
          </p>
        </div>

        <div className="p-8 md:p-12">
          <h2 className="text-2xl font-bold text-slate-900">Admin login</h2>
          <p className="mt-2 text-sm text-slate-600">Use your Supabase Authentication admin account.</p>

          {configError ? (
            <div className="mt-6 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{configError}</div>
          ) : null}

          <form onSubmit={handleSubmit} className="mt-8 space-y-4">
            <Input
              label="Email"
              type="email"
              value={form.email}
              onChange={(event) => setForm((current) => ({ ...current, email: event.target.value }))}
              placeholder="admin@ikea.com"
            />
            <Input
              label="Password"
              type="password"
              value={form.password}
              onChange={(event) => setForm((current) => ({ ...current, password: event.target.value }))}
              placeholder="••••••••"
            />

            {error ? <div className="rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div> : null}

            <Button type="submit" disabled={submitting} className="w-full">
              {submitting ? 'Signing in...' : 'Sign in'}
            </Button>
          </form>
        </div>
      </div>
    </div>
  )
}
