export default async function handler() {
  return new Response(
    JSON.stringify({ ok: true, message: 'Placeholder function. Connect Resend or another provider here.' }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  )
}
