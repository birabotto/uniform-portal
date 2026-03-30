import { createClient } from '@supabase/supabase-js'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Content-Type': 'application/json',
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify(body),
  }
}

export async function handler(event) {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 200, headers: corsHeaders, body: '' }
  }

  if (event.httpMethod !== 'GET') {
    return json(405, { error: 'Method not allowed' })
  }

  const supabaseUrl = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY

  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, {
      error: 'Missing VITE_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in Netlify environment variables.',
    })
  }

  try {
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data, error } = await admin.auth.admin.listUsers()

    if (error) {
      return json(400, { error: error.message })
    }

    const users = (data?.users || [])
      .map((user) => ({
        id: user.id,
        email: user.email,
        full_name: user.user_metadata?.full_name || '',
        created_at: user.created_at,
        confirmed_at: user.email_confirmed_at,
        status: user.email_confirmed_at ? 'confirmed' : 'pending confirmation',
      }))
      .sort((a, b) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime())

    return json(200, { users })
  } catch (error) {
    return json(500, { error: error.message || 'Unexpected error' })
  }
}
