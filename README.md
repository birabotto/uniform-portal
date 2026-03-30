# Uniform Portal

Professional Supabase + Netlify version of the IKEA-style uniform portal.

## What changed in this version

- removed the dependency on `public.profiles`
- removed admin role checks
- any authenticated Supabase Auth user can access `/admin`
- public request flow still works through secure RPC functions
- dashboard user management now reads and creates users directly in Supabase Auth through Netlify Functions
- frontend accepts either `VITE_SUPABASE_ANON_KEY` or `VITE_SUPABASE_PUBLISHABLE_KEY`

## Local setup

Create `.env.local` in the project root:

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_key
VITE_FUNCTIONS_BASE_URL=/.netlify/functions
RESEND_API_KEY=your_resend_api_key
FROM_EMAIL="Uniform Portal <no-reply@example.com>"
PC_EMAIL=pc@example.com
```

Server-side Netlify env values:

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
RESEND_API_KEY=your_resend_api_key
FROM_EMAIL="Uniform Portal <no-reply@example.com>"
PC_EMAIL=pc@example.com
```

## Run locally

```bash
yarn
npx netlify dev
```

## SQL

Run this file in the Supabase SQL Editor:

- `supabase/schema-no-profiles-professional.sql`

That schema keeps RLS enabled and opens dashboard tables to authenticated users only.

## Main RPCs used by the app

- `lookup_employee_by_id(text)`
- `submit_uniform_request(text, text, text, text, text, text)`
- `add_stock(uuid, integer)`
- `set_request_status(uuid, text, text, uuid)`
