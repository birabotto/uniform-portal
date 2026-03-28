import { useEffect, useState } from 'react'
import { Card, StatCard } from '../components/ui'
import { getDashboardData } from '../lib/portalApi'

function BarRow({ label, value, total }) {
  const width = total > 0 ? `${Math.max(6, Math.round((value / total) * 100))}%` : '0%'

  return (
    <div>
      <div className="mb-2 flex items-center justify-between text-sm text-slate-700">
        <span className="font-medium">{label}</span>
        <span>{value}</span>
      </div>
      <div className="h-3 rounded-full bg-[#edf2f7]">
        <div className="h-3 rounded-full bg-[#dbe6f6]" style={{ width }} />
      </div>
    </div>
  )
}

export default function AdminDashboardPage() {
  const [state, setState] = useState({ loading: true, error: '', data: null })

  useEffect(() => {
    let ignore = false

    async function load() {
      try {
        const data = await getDashboardData()
        if (!ignore) setState({ loading: false, error: '', data })
      } catch (error) {
        if (!ignore) setState({ loading: false, error: error.message || 'Failed to load dashboard.', data: null })
      }
    }

    load()
    return () => {
      ignore = true
    }
  }, [])

  if (state.loading) {
    return <div className="rounded-[28px] border border-softBorder bg-white p-6 shadow-soft text-slate-600">Loading dashboard...</div>
  }

  if (state.error) {
    return <div className="rounded-[28px] border border-red-200 bg-red-50 p-6 text-sm text-red-700">{state.error}</div>
  }

  const { data } = state
  const summary = data.summary
  const statusRows = ['pending', 'approved', 'ordered', 'completed', 'cancelled', 'special_request'].map((status) => {
    const match = data.requestsByStatus.find((item) => item.status === status)
    return { status, total: Number(match?.total_requests || 0) }
  })

  const totalStatus = statusRows.reduce((acc, item) => acc + item.total, 0)

  return (
    <div className="space-y-6">
      <section className="rounded-[30px] bg-gradient-to-r from-[#2559aa] to-[#3978d5] px-6 py-6 text-white shadow-[0_24px_60px_rgba(8,59,112,0.16)] md:px-7 md:py-7">
        <p className="text-xs font-extrabold uppercase tracking-[0.34em] text-ikeaYellow">Operations</p>
        <h2 className="mt-3 text-4xl font-extrabold leading-tight">Uniform operations overview</h2>
        <p className="mt-4 max-w-4xl text-lg leading-8 text-blue-50">
          Track pending requests, watch low-stock items, and monitor request flow before employees run out of the right uniform sizes.
        </p>
      </section>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
        <StatCard label="Pending" value={summary.pendingRequests} helper="Stock is reserved while requests wait for review." tone="yellow" />
        <StatCard label="Approved" value={summary.approvedRequests} helper="Approved requests continue holding stock." tone="blue" />
        <StatCard label="Fulfilled" value={summary.fulfilledRequests} helper="Completed requests already reduced real stock." />
        <StatCard label="Special requests" value={summary.specialRequests} helper="No stock available or size-up fallback found." />
        <StatCard label="Low stock" value={summary.lowStockCount} helper="Items at or below reorder level need attention." />
      </div>

      <div className="grid gap-6 xl:grid-cols-[1.45fr_0.95fr]">
        <Card title="Request status distribution" subtitle="A quick look at the current queue and completed work.">
          <div className="space-y-5">
            {statusRows.map((item) => (
              <BarRow key={item.status} label={item.status.replaceAll('_', ' ')} value={item.total} total={totalStatus} />
            ))}
          </div>
        </Card>

        <Card title="Most requested items" subtitle="Top combinations employees are asking for right now.">
          {data.mostOrderedItems.length ? (
            <div className="space-y-3">
              {data.mostOrderedItems.slice(0, 6).map((item, index) => (
                <div key={`${item.product_type}-${item.requested_size}-${index}`} className="rounded-[20px] bg-[#f5f8fc] px-4 py-4 text-sm text-slate-600">
                  <p className="font-bold text-slate-900">{item.product_type}</p>
                  <p className="mt-1">{item.style || 'Standard'} • {item.colour || 'Default'} • {item.requested_size}</p>
                  <p className="mt-2 text-xs font-semibold uppercase tracking-wide text-ikeaBlue">{item.total_requests} request(s)</p>
                </div>
              ))}
            </div>
          ) : (
            <div className="rounded-[20px] bg-[#f5f8fc] px-5 py-4 text-sm text-slate-500">Requests will show here after the QR page is used.</div>
          )}
        </Card>
      </div>
    </div>
  )
}
