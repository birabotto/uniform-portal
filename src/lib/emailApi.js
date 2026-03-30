const functionsBaseUrl =
  import.meta.env.VITE_FUNCTIONS_BASE_URL || '/.netlify/functions'

async function postEmail(path, payload) {
  const response = await fetch(`${functionsBaseUrl}/${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  })

  const data = await response.json()

  if (!response.ok) {
    throw new Error(data?.error || 'Failed to send email :(')
  }

  return data
}

export function sendNewRequestEmail(payload) {
  return postEmail('send-new-request-email', payload)
}

export function sendStatusUpdateEmail(payload) {
  return postEmail('send-status-update-email', payload)
}
