import { useEffect, useMemo, useState } from 'react'
import Badge from '../components/Badge'
import EmptyState from '../components/EmptyState'
import KpiCard from '../components/KpiCard'
import PageHeader from '../components/PageHeader'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'
import { sendStatusUpdateEmail } from '../lib/emailApi'

const statusOptions = ['pending', 'approved', 'ordered', 'fulfilled', 'rejected', 'cancelled']

function getLines(request) {
  return Array.isArray(request.request_items) ? request.request_items : []
}

function firstLine(request) {
  return getLines(request)[0] ?? {}
}

export default function AdminRequestsPage() {
  const { user } = useAuth()
  const [requests, setRequests] = useState([])
  const [historyByRequest, setHistoryByRequest] = useState({})
  const [query, setQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState(null)
  const [messages, setMessages] = useState({})
  const [loadError, setLoadError] = useState('')

  async function loadData() {
    if (!supabase) return
    setLoading(true)
    setLoadError('')
    const [{ data: requestRows, error: requestError }, { data: historyRows, error: historyError }] = await Promise.all([
      supabase
        .from('uniform_requests')
        .select(`
          *,
          request_items (
            id,
            product_type,
            fit,
            colour,
            requested_size,
            suggested_size,
            quantity,
            line_status
          )
        `)
        .order('created_at', { ascending: false }),
      supabase.from('request_history').select('*').order('created_at', { ascending: false }),
    ])

    if (requestError || historyError) {
      setLoadError(requestError?.message || historyError?.message || 'Failed to load requests')
    }

    const groupedHistory = (historyRows ?? []).reduce((acc, item) => {
      acc[item.request_id] = acc[item.request_id] || []
      acc[item.request_id].push(item)
      return acc
    }, {})

    setRequests(requestRows ?? [])
    setHistoryByRequest(groupedHistory)
    setLoading(false)
  }

  useEffect(() => {
    loadData()
  }, [])

  const filteredRequests = useMemo(() => {
    return requests.filter((request) => {
      const lineText = getLines(request)
        .map((line) => `${line.product_type || ''} ${line.fit || ''} ${line.colour || ''} ${line.requested_size || ''}`)
        .join(' ')

      const haystack = `${request.employee_id || ''} ${request.employee_name} ${request.employee_email} ${request.employee_department || ''} ${lineText}`.toLowerCase()
      const matchesQuery = !query || haystack.includes(query.toLowerCase())
      const matchesStatus = statusFilter === 'all' || request.status === statusFilter
      return matchesQuery && matchesStatus
    })
  }, [requests, query, statusFilter])

  const summary = useMemo(() => ({
    total: requests.length,
    pending: requests.filter((request) => request.status === 'pending').length,
    approved: requests.filter((request) => request.status === 'approved').length,
    special: requests.filter((request) => request.fulfillment_mode === 'special_request').length,
  }), [requests])

  async function handleStatusChange(request, nextStatus) {
    if (!supabase) return
    setBusyId(request.id)

    const { error } = await supabase.rpc('set_request_status', {
      p_request_id: request.id,
      p_new_status: nextStatus,
      p_message: messages[request.id] || null,
      p_changed_by: user?.id || null,
    })

    if (error) {
      setBusyId(null)
      window.alert(error.message)
      return
    }

    const line = firstLine(request)

    try {
      await sendStatusUpdateEmail({
        employee_name: request.employee_name,
        employee_email: request.employee_email,
        product_type: line.product_type,
        fit: line.fit,
        colour: line.colour,
        requested_size: line.requested_size,
        suggested_size: line.suggested_size,
        status: nextStatus,
      })
    } catch (emailError) {
      console.error('Failed to send status update email:', emailError)
    }

    setMessages((current) => ({ ...current, [request.id]: '' }))
    await loadData()
    setBusyId(null)
  }

  if (loading) return <div className="text-slate-500">Loading requests...</div>
  if (requests.length === 0) return <EmptyState title="No requests yet" description="Requests created from the public QR page will appear here." />

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Workflow"
        title="Manage uniform requests"
        description="Search all past requests, review the full history log for each co-worker, and update status while keeping an audit trail."
      />

      {loadError ? <div className="rounded-[24px] border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">{loadError}</div> : null}

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <KpiCard label="All requests" value={summary.total} helper="Every request created from the QR page." accent="white" />
        <KpiCard label="Pending" value={summary.pending} helper="Stock is reserved while waiting for review." accent="yellow" />
        <KpiCard label="Approved" value={summary.approved} helper="Approved requests still keep stock reserved." accent="blue" />
        <KpiCard label="Special requests" value={summary.special} helper="Cases with no exact or size-up stock found." accent="white" />
      </div>

      <div className="card p-5">
        <div className="grid gap-4 lg:grid-cols-[1fr_220px]">
          <input className="field" placeholder="Search by employee ID, employee, email, department, product, fit, or size code..." value={query} onChange={(e) => setQuery(e.target.value)} />
          <select className="field" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
            <option value="all">All statuses</option>
            {statusOptions.map((status) => <option key={status} value={status}>{status}</option>)}
          </select>
        </div>
      </div>

      {!filteredRequests.length ? <EmptyState title="No matching requests" description="Try a different status filter or search term." /> : null}

      <div className="space-y-4">
        {filteredRequests.map((request) => (
          <div key={request.id} className="card p-5 sm:p-6">
            <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_360px]">
              <div>
                <div className="flex flex-wrap gap-2">
                  <Badge tone={request.status}>{request.status}</Badge>
                  <Badge tone={request.fulfillment_mode}>{request.fulfillment_mode.replace('_', ' ')}</Badge>
                </div>
                <h2 className="mt-4 text-xl font-semibold text-ink">{request.employee_name}</h2>
                <div className="mt-1 text-sm text-slate-500">{request.employee_email}</div>
                <div className="text-xs text-slate-400">Employee ID {request.employee_id || '—'} · {request.employee_department || 'No department'}</div>
                <div className="mt-4 rounded-[24px] bg-slate-50 p-4 text-sm text-slate-700">
                  <div className="space-y-3">
                    {getLines(request).map((line) => (
                      <div key={line.id} className="rounded-2xl bg-white p-4">
                        <div className="grid gap-3 sm:grid-cols-2">
                          <div><span className="font-semibold text-ink">Product:</span> {line.product_type || '—'}</div>
                          <div><span className="font-semibold text-ink">Fit:</span> {line.fit || '—'}</div>
                          <div><span className="font-semibold text-ink">Colour:</span> {line.colour || '—'}</div>
                          <div><span className="font-semibold text-ink">Requested size:</span> {line.requested_size || '—'}</div>
                          <div><span className="font-semibold text-ink">Suggested size:</span> {line.suggested_size || '—'}</div>
                          <div><span className="font-semibold text-ink">Qty:</span> {line.quantity || 1}</div>
                        </div>
                      </div>
                    ))}
                    <div><span className="font-semibold text-ink">Created:</span> {new Date(request.created_at).toLocaleString()}</div>
                  </div>
                  {request.notes ? <div className="mt-3"><span className="font-semibold text-ink">Employee notes:</span> {request.notes}</div> : null}
                </div>

                <div className="mt-5 rounded-[24px] border border-slate-200 bg-white p-4">
                  <div className="mb-3 text-sm font-semibold text-ink">History log</div>
                  <div className="space-y-3 text-sm text-slate-600">
                    {(historyByRequest[request.id] ?? []).map((item) => (
                      <div key={item.id} className="rounded-2xl bg-slate-50 p-3">
                        <div className="font-medium text-ink">{item.action.replace('_', ' ')}</div>
                        <div>{item.message || 'No message'}</div>
                        <div className="mt-1 text-xs text-slate-400">{new Date(item.created_at).toLocaleString()}</div>
                      </div>
                    ))}
                    {!(historyByRequest[request.id] ?? []).length ? <div>No history yet.</div> : null}
                  </div>
                </div>
              </div>

              <div className="rounded-[24px] bg-slate-50 p-4">
                <label className="field-label">Change status</label>
                <select
                  className="field"
                  value={request.status}
                  disabled={busyId === request.id}
                  onChange={(e) => handleStatusChange(request, e.target.value)}
                >
                  {statusOptions.map((status) => <option key={status} value={status}>{status}</option>)}
                </select>

                <div className="mt-4">
                  <label className="field-label">History message</label>
                  <textarea
                    className="field min-h-28"
                    placeholder="Example: Approved after stock check."
                    value={messages[request.id] ?? ''}
                    onChange={(e) => setMessages((current) => ({ ...current, [request.id]: e.target.value }))}
                  />
                </div>

                <div className="mt-4 rounded-2xl bg-white p-4 text-sm text-slate-600">
                  Pending reserves stock immediately. Approved and ordered keep the reservation. Rejected or cancelled release it.
                  Fulfilled reduces real stock.
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
