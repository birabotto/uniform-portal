import { useEffect, useMemo, useState } from 'react'
import { Badge, Button, Card, Input, PageHeader, Select, Textarea } from '../components/ui'
import { getRequestsWithHistory, updateRequestStatus } from '../lib/portalApi'

const statusOptions = ['pending', 'approved', 'ordered', 'completed', 'cancelled', 'special_request']

export default function AdminRequestsPage() {
  const [requests, setRequests] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [filters, setFilters] = useState({ search: '', status: 'all' })
  const [editing, setEditing] = useState({})

  async function loadRequests() {
    try {
      setLoading(true)
      const data = await getRequestsWithHistory()
      setRequests(data)
      setError('')
    } catch (error) {
      setError(error.message || 'Unable to load requests.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadRequests()
  }, [])

  const filteredRequests = useMemo(() => {
    return requests.filter((request) => {
      const matchesStatus = filters.status === 'all' || request.status === filters.status
      const search = filters.search.trim().toLowerCase()
      const haystack = [
        request.employee_name,
        request.employee_id,
        request.employee_email,
        request.product_type,
        request.requested_size,
        request.department,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()

      return matchesStatus && (!search || haystack.includes(search))
    })
  }, [requests, filters])

  async function handleStatusUpdate(requestId) {
    const draft = editing[requestId]
    if (!draft?.status) return

    try {
      await updateRequestStatus(requestId, draft.status, draft.note)
      await loadRequests()
    } catch (error) {
      setError(error.message || 'Failed to update status.')
    }
  }

  return (
    <>
      <PageHeader title="Request history" description="Filter all past co-worker requests, review history log, and change status with notes." />

      <Card title="Filters">
        <div className="grid gap-4 md:grid-cols-2">
          <Input
            label="Search"
            placeholder="Employee, email, item, size..."
            value={filters.search}
            onChange={(event) => setFilters((current) => ({ ...current, search: event.target.value }))}
          />
          <Select
            label="Status"
            value={filters.status}
            onChange={(event) => setFilters((current) => ({ ...current, status: event.target.value }))}
          >
            <option value="all">All statuses</option>
            {statusOptions.map((status) => (
              <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>
            ))}
          </Select>
        </div>
      </Card>

      {error ? <div className="rounded-3xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div> : null}
      {loading ? <div className="rounded-3xl border border-softBorder bg-white p-6 shadow-soft">Loading requests...</div> : null}

      <div className="space-y-4">
        {filteredRequests.map((request) => {
          const draft = editing[request.id] ?? { status: request.status, note: request.admin_note || '' }

          return (
            <Card
              key={request.id}
              title={`${request.employee_name} • ${request.product_type}`}
              subtitle={`${request.employee_id} • ${request.employee_email} • ${new Date(request.created_at).toLocaleString()}`}
            >
              <div className="grid gap-5 lg:grid-cols-[1.2fr_0.8fr]">
                <div className="space-y-4">
                  <div className="grid gap-3 md:grid-cols-2">
                    <Info label="Department" value={request.department} />
                    <Info label="Requested size" value={request.requested_size} />
                    <Info label="Suggested size" value={request.suggested_size || '—'} />
                    <Info label="Current status" value={<Badge tone={request.status}>{request.status.replaceAll('_', ' ')}</Badge>} />
                  </div>

                  <div className="rounded-2xl bg-softBg p-4">
                    <p className="text-sm font-semibold text-slate-700">Item details</p>
                    <p className="mt-2 text-sm text-slate-600">
                      Style: {request.style || 'Standard'} • Colour: {request.colour || 'Default'} • Fit: {request.fit || '—'} • Sleeve: {request.sleeve || '—'}
                    </p>
                    {request.special_request_note ? (
                      <p className="mt-3 text-sm text-slate-600">Special request note: {request.special_request_note}</p>
                    ) : null}
                  </div>

                  <div>
                    <p className="mb-3 text-sm font-semibold text-slate-700">History log</p>
                    <div className="space-y-3">
                      {(request.request_status_history ?? []).length ? (
                        request.request_status_history.map((history) => (
                          <div key={history.id} className="rounded-2xl border border-softBorder p-4">
                            <div className="flex flex-wrap items-center gap-2">
                              <Badge tone={history.new_status}>{history.new_status.replaceAll('_', ' ')}</Badge>
                              <span className="text-xs text-slate-500">{new Date(history.created_at).toLocaleString()}</span>
                            </div>
                            {history.note ? <p className="mt-2 text-sm text-slate-600">{history.note}</p> : null}
                          </div>
                        ))
                      ) : (
                        <div className="rounded-2xl border border-dashed border-softBorder p-4 text-sm text-slate-500">No history available.</div>
                      )}
                    </div>
                  </div>
                </div>

                <div className="rounded-3xl border border-softBorder bg-softBg p-4">
                  <p className="text-sm font-semibold text-slate-800">Update request</p>
                  <div className="mt-4 space-y-4">
                    <Select
                      label="New status"
                      value={draft.status}
                      onChange={(event) =>
                        setEditing((current) => ({
                          ...current,
                          [request.id]: { ...draft, status: event.target.value },
                        }))
                      }
                    >
                      {statusOptions.map((status) => (
                        <option key={status} value={status}>{status.replaceAll('_', ' ')}</option>
                      ))}
                    </Select>

                    <Textarea
                      label="Admin note"
                      value={draft.note}
                      onChange={(event) =>
                        setEditing((current) => ({
                          ...current,
                          [request.id]: { ...draft, note: event.target.value },
                        }))
                      }
                      placeholder="Optional note for the history log"
                    />

                    <Button onClick={() => handleStatusUpdate(request.id)} className="w-full">
                      Save status
                    </Button>
                  </div>
                </div>
              </div>
            </Card>
          )
        })}

        {!loading && !filteredRequests.length ? (
          <div className="rounded-3xl border border-dashed border-softBorder bg-white p-6 text-sm text-slate-500 shadow-soft">
            No requests found with the current filters.
          </div>
        ) : null}
      </div>
    </>
  )
}

function Info({ label, value }) {
  return (
    <div className="rounded-2xl border border-softBorder p-4">
      <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">{label}</p>
      <div className="mt-2 text-sm font-medium text-slate-800">{value}</div>
    </div>
  )
}
