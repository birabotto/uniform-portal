import { supabase } from './supabase'

function throwIfNoSupabase() {
  if (!supabase) {
    throw new Error('Supabase is not configured.')
  }
}

export async function getDashboardData() {
  throwIfNoSupabase()

  const [
    requestsResult,
    lowStockResult,
    inventoryResult,
    employeesResult,
    sizeAnalyticsResult,
    itemAnalyticsResult,
    statusAnalyticsResult,
  ] = await Promise.all([
    supabase.from('uniform_requests').select('*').order('created_at', { ascending: false }),
    supabase.from('analytics_low_stock_items').select('*'),
    supabase.from('inventory_items').select('*').eq('is_active', true),
    supabase.from('employee_directory').select('*').eq('is_active', true),
    supabase.from('analytics_requested_sizes').select('*'),
    supabase.from('analytics_most_ordered_items').select('*'),
    supabase.from('analytics_requests_by_status').select('*'),
  ])

  const errors = [
    requestsResult.error,
    lowStockResult.error,
    inventoryResult.error,
    employeesResult.error,
    sizeAnalyticsResult.error,
    itemAnalyticsResult.error,
    statusAnalyticsResult.error,
  ].filter(Boolean)

  if (errors.length) {
    throw errors[0]
  }

  const requests = requestsResult.data ?? []
  const employees = employeesResult.data ?? []
  const lowStockItems = lowStockResult.data ?? []

  return {
    requests,
    lowStockItems,
    inventoryItems: inventoryResult.data ?? [],
    employees,
    requestedSizes: sizeAnalyticsResult.data ?? [],
    mostOrderedItems: itemAnalyticsResult.data ?? [],
    requestsByStatus: statusAnalyticsResult.data ?? [],
    summary: {
      totalRequests: requests.length,
      pendingRequests: requests.filter((item) => item.status === 'pending').length,
      approvedRequests: requests.filter((item) => item.status === 'approved').length,
      fulfilledRequests: requests.filter((item) => item.status === 'completed').length,
      specialRequests: requests.filter((item) => item.status === 'special_request').length,
      activeEmployees: employees.length,
      lowStockCount: lowStockItems.length,
    },
  }
}

export async function getRequestsWithHistory() {
  throwIfNoSupabase()

  const { data, error } = await supabase
    .from('uniform_requests')
    .select(`
      *,
      request_status_history (
        id,
        old_status,
        new_status,
        note,
        created_at
      )
    `)
    .order('created_at', { ascending: false })

  if (error) throw error
  return data ?? []
}

export async function updateRequestStatus(requestId, newStatus, adminNote = '') {
  throwIfNoSupabase()

  const { data, error } = await supabase.rpc('update_request_status', {
    p_request_id: requestId,
    p_new_status: newStatus,
    p_admin_note: adminNote || null,
  })

  if (error) throw error
  return data
}

export async function getEmployees() {
  throwIfNoSupabase()

  const { data, error } = await supabase
    .from('employee_directory')
    .select('*')
    .order('full_name', { ascending: true })

  if (error) throw error
  return data ?? []
}

export async function upsertEmployee(payload) {
  throwIfNoSupabase()

  if (payload.id) {
    const { data, error } = await supabase
      .from('employee_directory')
      .update({
        employee_id: payload.employee_id,
        full_name: payload.full_name,
        email: payload.email,
        department: payload.department,
        is_active: payload.is_active,
      })
      .eq('id', payload.id)
      .select()
      .single()

    if (error) throw error
    return data
  }

  const { data, error } = await supabase
    .from('employee_directory')
    .insert({
      employee_id: payload.employee_id,
      full_name: payload.full_name,
      email: payload.email,
      department: payload.department,
      is_active: payload.is_active ?? true,
    })
    .select()
    .single()

  if (error) throw error
  return data
}

export async function deleteEmployee(id) {
  throwIfNoSupabase()
  const { error } = await supabase.from('employee_directory').delete().eq('id', id)
  if (error) throw error
}

export async function getInventory() {
  throwIfNoSupabase()

  const { data, error } = await supabase.from('inventory_items').select('*').order('product_type')
  if (error) throw error
  return data ?? []
}

export async function getPublicRequestData() {
  throwIfNoSupabase()

  const { data, error } = await supabase
    .from('inventory_items')
    .select('*')
    .eq('is_active', true)
    .order('product_type')

  if (error) throw error
  return data ?? []
}

export async function saveInventoryItem(payload) {
  throwIfNoSupabase()

  if (payload.id) {
    const { data, error } = await supabase
      .from('inventory_items')
      .update({
        sku: payload.sku || null,
        product_type: payload.product_type,
        style: payload.style || null,
        colour: payload.colour || null,
        fit: payload.fit || null,
        sleeve: payload.sleeve || null,
        size: payload.size,
        stock_quantity: Number(payload.stock_quantity || 0),
        reorder_level: Number(payload.reorder_level || 0),
        is_active: payload.is_active ?? true,
      })
      .eq('id', payload.id)
      .select()
      .single()

    if (error) throw error
    return data
  }

  const { data, error } = await supabase
    .from('inventory_items')
    .insert({
      sku: payload.sku || null,
      product_type: payload.product_type,
      style: payload.style || null,
      colour: payload.colour || null,
      fit: payload.fit || null,
      sleeve: payload.sleeve || null,
      size: payload.size,
      stock_quantity: Number(payload.stock_quantity || 0),
      reorder_level: Number(payload.reorder_level || 0),
      is_active: payload.is_active ?? true,
    })
    .select()
    .single()

  if (error) throw error
  return data
}

export async function getEmployeeByEmployeeId(employeeId) {
  throwIfNoSupabase()

  const { data, error } = await supabase.rpc('get_employee_by_employee_id', {
    p_employee_id: employeeId,
  })

  if (error) throw error
  return data?.[0] ?? null
}

export async function submitUniformRequest(payload) {
  throwIfNoSupabase()

  const { data, error } = await supabase.rpc('submit_uniform_request', {
    p_employee_id: payload.employee_id,
    p_product_type: payload.product_type,
    p_style: payload.style || null,
    p_colour: payload.colour || null,
    p_fit: payload.fit || null,
    p_sleeve: payload.sleeve || null,
    p_requested_size: payload.requested_size,
    p_suggested_size: payload.suggested_size || null,
    p_special_request_note: payload.special_request_note || null,
  })

  if (error) throw error
  return data
}

export const sizeChart = [
  { product: 'T-Shirt', fit: 'Regular', xs: '34-36', s: '36-38', m: '38-40', l: '40-42', xl: '42-44', xxl: '44-46' },
  { product: 'Polo', fit: 'Regular', xs: '34-36', s: '36-38', m: '38-40', l: '40-42', xl: '42-44', xxl: '44-46' },
  { product: 'Jacket', fit: 'Unisex', xs: '32-34', s: '34-36', m: '38-40', l: '42-44', xl: '46-48', xxl: '50-52' },
  { product: 'Pants', fit: 'Regular', xs: '28-30', s: '30-32', m: '32-34', l: '34-36', xl: '36-38', xxl: '38-40' },
]
