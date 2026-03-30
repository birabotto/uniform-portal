const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
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

    console.log('TEST PC_EMAIL:', process.env.PC_EMAIL)
    console.log('TEST FROM_EMAIL:', process.env.FROM_EMAIL)

    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: process.env.FROM_EMAIL,
        to: [process.env.PC_EMAIL],
        subject: `PC Email Test ${new Date().toISOString()}`,
        html: `<p>Testing PC email delivery.</p>`,
      }),
    })

    const data = await resendResponse.json()

    console.log('TEST PC RESEND STATUS:', resendResponse.status)
    console.log('TEST PC RESEND RESPONSE:', JSON.stringify(data, null, 2))

    return {
      statusCode: resendResponse.ok ? 200 : resendResponse.status,
      headers: corsHeaders,
      body: JSON.stringify({ ok: resendResponse.ok, data }),
    }
  } catch (error) {
    console.error('TEST PC EMAIL ERROR:', error)

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: error.message }),
    }
  }
}
