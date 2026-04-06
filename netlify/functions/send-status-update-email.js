const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === 'OPTIONS') {
      return {
        statusCode: 200,
        headers: corsHeaders,
        body: '',
      }
    }

    if (event.httpMethod !== 'POST') {
      return {
        statusCode: 405,
        headers: corsHeaders,
        body: JSON.stringify({ error: 'Method not allowed' }),
      }
    }

    const body = JSON.parse(event.body || '{}')

    const {
      employee_name,
      employee_email,
      product_type,
      style,
      colour,
      requested_size,
      status,
    } = body

    const html = `
      <div style="font-family: Arial, sans-serif; background:#f5f7fa; padding:24px;">
        <div style="max-width:600px; margin:0 auto; background:#ffffff; border-radius:16px; overflow:hidden; border:1px solid #e5e7eb;">
          <div style="background:#0058A3; color:#ffffff; padding:20px; font-size:20px; font-weight:700;">
            IKEA Uniform Portal
          </div>

          <div style="padding:24px;">
            <h2 style="margin:0 0 16px; color:#111827;">Request Status Updated</h2>

            <p style="margin:8px 0;">Hello ${employee_name || 'there'},</p>
            <p style="margin:8px 0;">Your uniform request has been updated.</p>

            <p style="margin:8px 0;"><strong>Product:</strong> ${product_type || '-'}</p>
            <p style="margin:8px 0;"><strong>Style:</strong> ${style || '-'}</p>
            <p style="margin:8px 0;"><strong>Colour:</strong> ${colour || '-'}</p>
            <p style="margin:8px 0;"><strong>Requested Size:</strong> ${requested_size || '-'}</p>

            <div style="margin-top:20px; display:inline-block; background:#FFDA1A; color:#111827; padding:10px 14px; border-radius:999px; font-weight:700;">
              Status: ${status || '-'}
            </div>
          </div>
        </div>
      </div>
    `

    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: process.env.FROM_EMAIL,
        to: [employee_email],
        subject: 'Your uniform request status has changed',
        html,
      }),
    })

    const data = await resendResponse.json()

    if (!resendResponse.ok) {
      return {
        statusCode: resendResponse.status,
        headers: corsHeaders,
        body: JSON.stringify({
          error: data?.message || data?.error || 'Failed to send email',
          details: data,
        }),
      }
    }

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ success: true, data }),
    }
  } catch (error) {
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({
        error: error.message || 'Unexpected error',
      }),
    }
  }
}