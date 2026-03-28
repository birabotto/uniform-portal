import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { supabase, supabaseConfigError } from '../lib/supabase'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null)
  const [profile, setProfile] = useState(null)
  const [loading, setLoading] = useState(true)
  const [configError] = useState(supabaseConfigError)

  useEffect(() => {
    let mounted = true

    async function loadProfile(userId) {
      if (!supabase || !userId) {
        if (mounted) setProfile(null)
        return
      }

      const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).maybeSingle()
      if (!mounted) return

      if (error) {
        console.error('loadProfile error:', error)
        setProfile(null)
        return
      }

      setProfile(data ?? null)
    }

    async function bootstrap() {
      if (!supabase || supabaseConfigError) {
        if (mounted) setLoading(false)
        return
      }

      try {
        const { data, error } = await supabase.auth.getSession()
        if (error) {
          console.error('getSession error:', error)
        }

        const nextSession = data?.session ?? null
        if (!mounted) return
        setSession(nextSession)

        if (nextSession?.user?.id) {
          await loadProfile(nextSession.user.id)
        } else {
          setProfile(null)
        }
      } finally {
        if (mounted) setLoading(false)
      }
    }

    bootstrap()

    if (!supabase) {
      return () => {
        mounted = false
      }
    }

    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (_event, nextSession) => {
      if (!mounted) return
      setSession(nextSession)
      if (nextSession?.user?.id) {
        await loadProfile(nextSession.user.id)
      } else {
        setProfile(null)
      }
      setLoading(false)
    })

    return () => {
      mounted = false
      subscription.unsubscribe()
    }
  }, [])

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
      loading,
      configError,
      signIn,
      signOut,
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
