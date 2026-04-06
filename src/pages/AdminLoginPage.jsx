import { useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

export default function AdminLoginPage() {
  const { user, signIn, signOut, loading, configError } = useAuth()
  const [submitting, setSubmitting] = useState(false)
  const [errorMessage, setErrorMessage] = useState('')

  if (!loading && user) {
    return <Navigate to="/admin" replace />
  }

  async function handleSubmit(event) {
    event.preventDefault()
    if (submitting) return

    setSubmitting(true)
    setErrorMessage('')

    try {
      const formData = new FormData(event.currentTarget)
      const email = String(formData.get('email') || '')
      const password = String(formData.get('password') || '')

      const { error } = await signIn(email, password)
      if (error) setErrorMessage(error.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4 py-8">
      <div className="grid w-full max-w-6xl gap-6 lg:grid-cols-[1.1fr_0.9fr]">
        <div className="hidden rounded-[32px] bg-gradient-to-br from-[#0058A3] via-[#0A7BD8] to-[#004987] p-10 text-white shadow-soft lg:block">
          <div className="inline-flex rounded-full bg-[#FFDA1A] px-3 py-1 text-xs font-bold uppercase tracking-[0.24em] text-slate-900">IKEA Uniform Portal</div>
          <h1 className="mt-6 text-4xl font-bold leading-tight">Professional dashboard access for every authenticated Supabase user.</h1>
          <p className="mt-4 max-w-xl text-base text-blue-100">
            Sign in with any user registered in Supabase Auth to manage requests, stock, employees, and dashboard users.
            The public QR request page remains open for co-workers.
          </p>
          <div className="mt-10 grid gap-4 sm:grid-cols-2">
            <div className="rounded-[24px] bg-white/10 p-5 backdrop-blur">
              <div className="text-sm font-semibold">Public QR page</div>
              <div className="mt-2 text-sm text-blue-100">Mobile-first request flow with live availability preview.</div>
            </div>
            <div className="rounded-[24px] bg-white/10 p-5 backdrop-blur">
              <div className="text-sm font-semibold">Dashboard access</div>
              <div className="mt-2 text-sm text-blue-100">No profiles table, no admin role dependency, and no extra sync step.</div>
            </div>
          </div>
        </div>

        <div className="card w-full p-8 sm:p-10">
          <div className="mb-8">
            <div className="inline-flex rounded-full bg-[#FFDA1A] px-3 py-1 text-xs font-bold uppercase tracking-[0.24em] text-slate-900 lg:hidden">Dashboard login</div>
            <h2 className="mt-4 text-3xl font-bold text-ink">Sign in to the dashboard</h2>
            <p className="mt-2 text-sm text-slate-500">Any authenticated Supabase user can access the admin workspace.</p>
          </div>

          {configError ? <div className="mb-4 rounded-2xl bg-red-50 p-4 text-sm text-red-700">{configError}</div> : null}
          {errorMessage ? <div className="mb-4 rounded-2xl bg-red-50 p-4 text-sm text-red-700">{errorMessage}</div> : null}
          {!loading && user ? (
            <div className="mb-4 rounded-2xl bg-emerald-50 p-4 text-sm text-emerald-800">
              You are signed in as <strong>{user.email}</strong>.
              <button className="btn-secondary mt-3 w-full" onClick={signOut} type="button">Sign out and use another account</button>
            </div>
          ) : null}

          <form className="space-y-5" onSubmit={handleSubmit}>
            <div>
              <label className="field-label">Email</label>
              <input className="field" name="email" type="email" placeholder="dashboard@company.com" required />
            </div>
            <div>
              <label className="field-label">Password</label>
              <input className="field" name="password" type="password" placeholder="••••••••" required />
            </div>
            <button className="btn-primary w-full" disabled={submitting || !!configError} type="submit">
              {submitting ? 'Signing in...' : 'Login'}
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}
