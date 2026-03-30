import { useEffect, useMemo, useState } from 'react'
import Badge from '../components/Badge'
import EmptyState from '../components/EmptyState'
import KpiCard from '../components/KpiCard'
import PageHeader from '../components/PageHeader'
import SimpleBarChart from '../components/SimpleBarChart'
import { supabase } from '../lib/supabase'

const statusOrder = ['pending', 'approved', 'ordered', 'fulfilled', 'rejected', 'cancelled']

function getRequestLines(request) {
  if (Array.isArray(request.request_items) && request.request_items.length) {
    return request.request_items
  }

  if (request.product_type || request.style || request.colour || request.requested_size) {
    return [
      {
        product_type: request.product_type,
        style: request.style,
        colour: request.colour,
        requested_size: request.requested_size,
        suggested_size: request.suggested_size,
        quantity: request.quantity ?? 1,
      },
    ]
  }

  return []
}

function makeItemLabel(item) {
  return [item?.product_type, item?.style, item?.colour].filter(Boolean).join(' · ') || 'Item details unavailable'
}

export default function AdminDashboardPage() {
  const [requests, setRequests] = useState([])
  const [inventory, setInventory] = useState([])
  const [history, setHistory] = useState([])
  const [employees, setEmployees] = useState([])
  const [analyticsRows, setAnalyticsRows] = useState([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')

  async function load() {
    if (!supabase) return
    setLoading(true)
    setLoadError('')

    const [
      requestsResponse,
      inventoryResponse,
      historyResponse,
      employeeResponse,
      analyticsResponse,
    ] = await Promise.all([
      supabase
        .from('uniform_requests')
        .select(`
          *,
          request_items (
            id,
            product_type,
            style,
            colour,
            requested_size,
            suggested_size,
            quantity,
            line_status
          )
        `)
        .order('created_at', { ascending: false }),
      supabase.from('inventory_items').select('*').order('product_type'),
      supabase.from('request_history').select('*').order('created_at', { ascending: false }).limit(10),
      supabase.from('employees').select('*').order('full_name'),
      supabase.from('v_request_analytics').select('*').order('total_qty', { ascending: false }),
    ])

    const firstError =
      requestsResponse.error ||
      inventoryResponse.error ||
      historyResponse.error ||
      employeeResponse.error ||
      analyticsResponse.error

    if (firstError) {
      console.error('Admin dashboard load error:', firstError)
      setLoadError(firstError.message)
    }

    setRequests(requestsResponse.data ?? [])
    setInventory(inventoryResponse.data ?? [])
    setHistory(historyResponse.data ?? [])
    setEmployees(employeeResponse.data ?? [])
    setAnalyticsRows(analyticsResponse.data ?? [])
    setLoading(false)
  }

  useEffect(() => {
    load()
  }, [])

  const stats = useMemo(() => {
    const pending = requests.filter((item) => item.status === 'pending').length
    const approved = requests.filter((item) => item.status === 'approved').length
    const fulfilled = requests.filter((item) => item.status === 'fulfilled').length
    const lowStock = inventory.filter((item) => item.stock_quantity - item.reserved_quantity <= item.reorder_level).length
    return { pending, approved, fulfilled, lowStock }
  }, [requests, inventory])

  const requestStatusChart = useMemo(() => {
    return statusOrder.map((status) => ({
      label: status.replace('_', ' '),
      value: requests.filter((item) => item.status === status).length,
    }))
  }, [requests])

  const derivedAnalytics = useMemo(() => {
    const map = new Map()

    requests.forEach((request) => {
      const progressed = ['approved', 'ordered', 'fulfilled'].includes(request.status) ? 1 : 0
      getRequestLines(request).forEach((line) => {
        const key = [line.product_type, line.style, line.colour, line.requested_size].join('||')
        const existing = map.get(key) ?? {
          product_type: line.product_type,
          style: line.style,
          colour: line.colour,
          requested_size: line.requested_size,
          item_label: makeItemLabel(line),
          total_qty: 0,
          progressed_count: 0,
        }

        existing.total_qty += Number(line.quantity ?? 1)
        existing.progressed_count += progressed
        map.set(key, existing)
      })
    })

    return Array.from(map.values())
  }, [requests])

  const analytics = analyticsRows.length ? analyticsRows : derivedAnalytics

  const topRequestedSizes = useMemo(() => {
    const counts = analytics.reduce((acc, row) => {
      const size = row.size ?? row.requested_size ?? 'Unknown'
      const quantity = Number(row.total_qty ?? row.value ?? 0)
      acc[size] = (acc[size] || 0) + quantity
      return acc
    }, {})

    return Object.entries(counts)
      .map(([label, value]) => ({ label, value }))
      .sort((a, b) => b.value - a.value)
      .slice(0, 6)
  }, [analytics])

  const mostOrderedItems = useMemo(() => {
    return analytics
      .map((row) => ({
        label: row.item_label ?? makeItemLabel(row),
        value: Number(row.progressed_count ?? row.total_qty ?? 0),
      }))
      .filter((item) => item.value > 0)
      .sort((a, b) => b.value - a.value)
      .slice(0, 5)
  }, [analytics])

  const lowStockItems = useMemo(() => {
    return inventory
      .filter((item) => item.stock_quantity - item.reserved_quantity <= item.reorder_level)
      .sort((a, b) => a.stock_quantity - a.reserved_quantity - (b.stock_quantity - b.reserved_quantity))
      .slice(0, 6)
  }, [inventory])

  const requestsByDepartment = useMemo(() => {
    const counts = requests.reduce((acc, row) => {
      const department = row.employee_department || 'Unassigned'
      acc[department] = (acc[department] || 0) + 1
      return acc
    }, {})

    return Object.entries(counts)
      .map(([label, value]) => ({ label, value }))
      .sort((a, b) => b.value - a.value)
      .slice(0, 5)
  }, [requests])

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Operations"
        title="Uniform operations overview"
        description="Track request demand, requested sizes, most ordered items, employee activity, and low-stock risks in one dashboard."
      />

      {loadError ? (
        <div className="rounded-[24px] border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          Some dashboard data could not be loaded: {loadError}
        </div>
      ) : null}

      <div className="flex justify-end">
        <button className="btn-secondary" onClick={load} type="button" disabled={loading}>
          {loading ? 'Refreshing...' : 'Refresh data'}
        </button>
      </div>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
        <KpiCard label="Pending" value={stats.pending} helper="Reserved stock waiting for review." accent="yellow" />
        <KpiCard label="Approved" value={stats.approved} helper="Approved requests still holding inventory." accent="blue" />
        <KpiCard label="Fulfilled" value={stats.fulfilled} helper="Requests already completed and deducted from stock." accent="white" />
        <KpiCard label="Employees" value={employees.length} helper="Imported employee records available for lookup." accent="white" />
        <KpiCard label="Low stock" value={stats.lowStock} helper="Items at or below reorder level." accent="white" />
      </div>

      <div className="grid gap-6 xl:grid-cols-2">
        <div className="card p-6">
          <h2 className="text-xl font-semibold text-ink">Request status distribution</h2>
          <p className="mt-1 text-sm text-slate-500">See how requests are moving through the workflow.</p>
          <div className="mt-5">
            <SimpleBarChart items={requestStatusChart} />
          </div>
        </div>

        <div className="card p-6">
          <h2 className="text-xl font-semibold text-ink">Frequently requested sizes</h2>
          <p className="mt-1 text-sm text-slate-500">Use this to decide which sizes should be replenished first.</p>
          <div className="mt-5">
            <SimpleBarChart items={topRequestedSizes} emptyLabel="Requested sizes will show up after employees submit requests." />
          </div>
        </div>
      </div>

      <div className="grid gap-6 xl:grid-cols-2">
        <div className="card p-6">
          <h2 className="text-xl font-semibold text-ink">Most ordered items</h2>
          <p className="mt-1 text-sm text-slate-500">Top combinations that reached ordered, approved, or fulfilled status.</p>
          <div className="mt-5">
            <SimpleBarChart items={mostOrderedItems} emptyLabel="Ordered items will appear here after admin approvals." />
          </div>
        </div>

        <div className="card p-6">
          <h2 className="text-xl font-semibold text-ink">Requests by department</h2>
          <p className="mt-1 text-sm text-slate-500">Spot departments generating the most demand.</p>
          <div className="mt-5">
            <SimpleBarChart items={requestsByDepartment} emptyLabel="Department activity will appear after requests are submitted." />
          </div>
        </div>
      </div>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.1fr)_minmax(320px,0.9fr)]">
        <div className="card p-6">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h2 className="text-xl font-semibold text-ink">Recent co-worker requests</h2>
              <p className="mt-1 text-sm text-slate-500">Latest items submitted from the QR page.</p>
            </div>
          </div>

          {!requests.length ? (
            <div className="mt-4"><EmptyState title="No requests yet" description="Requests created from the public QR page will appear here." /></div>
          ) : (
            <div className="mt-5 space-y-4">
              {requests.slice(0, 6).map((request) => {
                const lines = getRequestLines(request)
                return (
                  <div key={request.id} className="rounded-[24px] border border-slate-200 bg-slate-50 p-4">
                    <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                      <div>
                        <div className="flex flex-wrap gap-2">
                          <Badge tone={request.status}>{request.status}</Badge>
                          <Badge tone={request.fulfillment_mode}>{request.fulfillment_mode.replace('_', ' ')}</Badge>
                        </div>
                        <div className="mt-3 font-semibold text-ink">{request.employee_name}</div>
                        <div className="text-sm text-slate-500">{request.employee_email}</div>
                        <div className="text-xs text-slate-400">{request.employee_department || 'No department'} · ID {request.employee_id || '—'}</div>
                      </div>
                      <div className="space-y-1 text-sm text-slate-600">
                        {lines.map((line, index) => (
                          <div key={`${request.id}-${index}`}>
                            {makeItemLabel(line)} · {line.requested_size || 'No size'}
                            {line.suggested_size ? ` → ${line.suggested_size}` : ''}
                          </div>
                        ))}
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>

        <div className="space-y-6">
          <div className="card p-6">
            <h2 className="text-xl font-semibold text-ink">Low stock spotlight</h2>
            <div className="mt-4 space-y-3">
              {!lowStockItems.length ? (
                <div className="rounded-2xl bg-slate-50 p-4 text-sm text-slate-500">All active items are above their reorder level.</div>
              ) : (
                lowStockItems.map((item) => {
                  const available = Math.max(item.stock_quantity - item.reserved_quantity, 0)
                  return (
                    <div key={item.id} className="rounded-[24px] border border-slate-200 p-4">
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <div className="font-semibold text-ink">{item.product_type} · {item.style}</div>
                          <div className="text-sm text-slate-500">{item.colour} · {item.size}</div>
                        </div>
                        <Badge tone={available <= 0 ? 'rejected' : 'low'}>{available <= 0 ? 'Out of stock' : `${available} free`}</Badge>
                      </div>
                    </div>
                  )
                })
              )}
            </div>
          </div>

          <div className="card p-6">
            <h2 className="text-xl font-semibold text-ink">Latest history activity</h2>
            <div className="mt-4 space-y-3">
              {history.map((item) => (
                <div key={item.id} className="rounded-[24px] border border-slate-200 p-4">
                  <div className="font-semibold text-ink">{item.action.replace('_', ' ')}</div>
                  <div className="mt-1 text-sm text-slate-600">{item.message || 'No message provided.'}</div>
                  <div className="mt-2 text-xs text-slate-400">{new Date(item.created_at).toLocaleString()}</div>
                </div>
              ))}
              {!history.length ? <div className="rounded-2xl bg-slate-50 p-4 text-sm text-slate-500">History entries will appear after requests are created or updated.</div> : null}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
