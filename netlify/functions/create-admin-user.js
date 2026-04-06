import { createClient } from '@supabase/supabase-js'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
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

  if (event.httpMethod !== 'POST') {
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
    const payload = JSON.parse(event.body || '{}')
    const email = String(payload.email || '').trim().toLowerCase()
    const fullName = String(payload.full_name || '').trim()
    const password = String(payload.password || '').trim()

    if (!email || !fullName || !password) {
      return json(400, { error: 'full_name, email, and password are required.' })
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: createdUser, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    })

    if (createError) {
      return json(400, { error: createError.message })
    }

    const user = createdUser?.user

    if (!user?.id) {
      return json(500, { error: 'User was created but no user id was returned.' })
    }

    return json(200, {
      success: true,
      user: {
        id: user.id,
        email: user.email,
        full_name: user.user_metadata?.full_name || fullName,
        confirmed_at: user.email_confirmed_at,
      },
    })
  } catch (error) {
    return json(500, { error: error.message || 'Unexpected error' })
  }
}
