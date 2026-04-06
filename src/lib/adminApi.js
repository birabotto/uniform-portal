const functionsBaseUrl =
  import.meta.env.VITE_FUNCTIONS_BASE_URL || '/.netlify/functions'

async function parseJson(response) {
  return response.json().catch(() => ({}))
}

async function postJson(path, payload) {
  const response = await fetch(`${functionsBaseUrl}/${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  })

  const data = await parseJson(response)

  if (!response.ok) {
    throw new Error(data?.error || 'Request failed')
  }

  return data
}

async function getJson(path) {
  const response = await fetch(`${functionsBaseUrl}/${path}`)
  const data = await parseJson(response)

  if (!response.ok) {
    throw new Error(data?.error || 'Request failed')
  }

  return data
}

export function createAdminUser(payload) {
  return postJson('create-admin-user', payload)
}

export function listDashboardUsers() {
  return getJson('list-dashboard-users')
}
