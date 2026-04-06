import { createContext, useContext, useEffect, useMemo, useRef, useState } from 'react'
import { supabase, supabaseConfigError } from '../lib/supabase'

const AuthContext = createContext(null)

function mapUserToProfile(user) {
  if (!user) return null

  return {
    id: user.id,
    full_name: user.user_metadata?.full_name || user.email?.split('@')[0] || 'Dashboard user',
    email: user.email || '',
    access_label: 'dashboard_user',
  }
}

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null)
  const [profile, setProfile] = useState(null)
  const [loading, setLoading] = useState(true)
  const [configError] = useState(supabaseConfigError)
  const mountedRef = useRef(true)

  async function loadProfile(user) {
    const nextProfile = mapUserToProfile(user)
    if (mountedRef.current) {
      setProfile(nextProfile)
    }
    return nextProfile
  }

  async function syncSession(nextSession) {
    setSession(nextSession)

    if (nextSession?.user) {
      await loadProfile(nextSession.user)
    } else {
      setProfile(null)
    }
  }

  useEffect(() => {
    mountedRef.current = true

    async function bootstrap() {
      if (!supabase || supabaseConfigError) {
        if (mountedRef.current) setLoading(false)
        return
      }

      try {
        const { data, error } = await supabase.auth.getSession()

        if (error) {
          console.error('getSession error:', error)
        }

        if (!mountedRef.current) return
        await syncSession(data?.session ?? null)
      } finally {
        if (mountedRef.current) setLoading(false)
      }
    }

    bootstrap()

    if (!supabase) {
      return () => {
        mountedRef.current = false
      }
    }

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      if (!mountedRef.current) return
      setTimeout(async () => {
        if (!mountedRef.current) return
        setLoading(true)
        try {
          await syncSession(nextSession)
        } finally {
          if (mountedRef.current) setLoading(false)
        }
      }, 0)
    })

    return () => {
      mountedRef.current = false
      subscription.unsubscribe()
    }
  }, [configError])

  async function signIn(email, password) {
    if (!supabase) {
      return { error: { message: supabaseConfigError || 'Supabase is not configured' } }
    }

    return supabase.auth.signInWithPassword({ email, password })
  }

  async function signOut() {
    if (!supabase) return
    return supabase.auth.signOut()
  }

  const value = useMemo(
    () => ({
      session,
      user: session?.user ?? null,
      profile,
      isAdmin: Boolean(session?.user),
      loading,
      configError,
      signIn,
      signOut,
      refreshProfile: () => (session?.user ? loadProfile(session.user) : Promise.resolve(null)),
    }),
    [session, profile, loading, configError]
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used within AuthProvider')
  return context
}
