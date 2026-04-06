// Supabase Edge Function placeholder for approval emails.
// Configure RESEND_API_KEY and FROM_EMAIL in Supabase project secrets before deployment.

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' } })
  }

  const body = await req.json().catch(() => ({}))

  return new Response(
    JSON.stringify({
      ok: true,
      message: 'Placeholder function deployed. Connect your email provider here.',
      request: body,
    }),
    {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    }
  )
})
