
import { useEffect, useMemo, useState } from 'react'
import Badge from '../components/Badge'
import EmptyState from '../components/EmptyState'
import PageHeader from '../components/PageHeader'
import { supabase } from '../lib/supabase'
import { formatInventoryLabel, sortSizes } from '../lib/uniformCatalog'

export default function AdminInventoryPage() {
  const [items, setItems] = useState([])
  const [savingId, setSavingId] = useState(null)
  const [query, setQuery] = useState('')
  const [restockAmounts, setRestockAmounts] = useState({})
  const [message, setMessage] = useState('')

  useEffect(() => {
    async function load() {
      if (!supabase) return
      const { data } = await supabase
        .from('inventory_items')
        .select('*')
        .order('product_type')
        .order('fit')
      setItems((data ?? []).sort((a, b) => sortSizes(a.size, b.size)))
    }
    load()
  }, [])

  async function updateQuantity(id, nextQuantity) {
    if (!supabase) return
    setSavingId(id)
    setMessage('')
    const quantity = Math.max(Number(nextQuantity) || 0, 0)
    const { error } = await supabase.from('inventory_items').update({ stock_quantity: quantity }).eq('id', id)
    if (error) {
      setMessage(error.message)
    } else {
      setItems((current) => current.map((item) => (item.id === id ? { ...item, stock_quantity: quantity } : item)))
      setMessage('Stock quantity updated.')
    }
    setSavingId(null)
  }

  async function addStock(item) {
    if (!supabase) return
    const amount = Math.max(Number(restockAmounts[item.id]) || 0, 0)
    if (!amount) return

    setSavingId(item.id)
    setMessage('')

    const { error } = await supabase.rpc('add_stock', {
      p_item_id: item.id,
      p_amount: amount,
    })

    if (error) {
      setMessage(error.message)
      setSavingId(null)
      return
    }

    setItems((current) =>
      current.map((row) =>
        row.id === item.id ? { ...row, stock_quantity: Number(row.stock_quantity) + amount } : row
      )
    )
    setRestockAmounts((current) => ({ ...current, [item.id]: '' }))
    setMessage(`Added ${amount} unit${amount === 1 ? '' : 's'} to ${item.sku}.`)
    setSavingId(null)
  }

  const filteredItems = useMemo(() => {
    return items
      .filter((item) => {
        const text = `${item.sku} ${item.product_type} ${item.fit || ''} ${item.size} ${item.location || ''}`.toLowerCase()
        return !query || text.includes(query.toLowerCase())
      })
      .sort((a, b) => {
        const productCompare = String(a.product_type || '').localeCompare(String(b.product_type || ''))
        if (productCompare !== 0) return productCompare
        const fitCompare = String(a.fit || '').localeCompare(String(b.fit || ''))
        if (fitCompare !== 0) return fitCompare
        return sortSizes(a.size, b.size)
      })
  }, [items, query])

  if (items.length === 0) {
    return <EmptyState title="No inventory found" description="Run the latest schema.sql in Supabase to load the inventory catalog and stock seed." />
  }

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Stock control"
        title="Inventory management"
        description="Aligned to the workbook layout: product, fit, size code, location, stock, ordered, dry cleaned, reserved, and available quantities."
      />

      {message ? <div className="card p-4 text-sm text-slate-700">{message}</div> : null}

      <div className="card space-y-4 p-5">
        <input
          className="field"
          placeholder="Search by product, fit, size code, SKU, or location"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <div className="rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-600">
          This page follows the inventory workbook structure and keeps the IKEA size codes like <strong>CD</strong>, <strong>EF</strong>, and <strong>KN</strong>.
        </div>
      </div>

      <div className="space-y-4 lg:hidden">
        {filteredItems.map((item) => {
          const stock = Number(item.stock_quantity) || 0
          const reserved = Number(item.reserved_quantity) || 0
          const free = Math.max(stock - reserved, 0)
          const isLow = free <= item.reorder_level
          return (
            <div key={item.id} className="card space-y-4 p-5">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="font-semibold text-ink">{formatInventoryLabel(item)}</div>
                  <div className="text-sm text-slate-500">{item.location || 'Uniform Room'} · {item.sku}</div>
                </div>
                <Badge tone={isLow ? 'low' : 'healthy'}>{isLow ? 'Low stock' : 'Healthy'}</Badge>
              </div>

              <div className="grid grid-cols-2 gap-3 text-sm">
                <div className="rounded-2xl bg-slate-50 p-3"><div className="text-slate-500">Stock</div><div className="mt-1 font-semibold text-ink">{stock}</div></div>
                <div className="rounded-2xl bg-slate-50 p-3"><div className="text-slate-500">Reserved</div><div className="mt-1 font-semibold text-ink">{reserved}</div></div>
                <div className="rounded-2xl bg-slate-50 p-3"><div className="text-slate-500">Available</div><div className="mt-1 font-semibold text-ink">{free}</div></div>
                <div className="rounded-2xl bg-slate-50 p-3"><div className="text-slate-500">Ordered</div><div className="mt-1 font-semibold text-ink">{Number(item.ordered_quantity) || 0}</div></div>
                <div className="rounded-2xl bg-slate-50 p-3"><div className="text-slate-500">Dry cleaned</div><div className="mt-1 font-semibold text-ink">{Number(item.dry_cleaned_quantity) || 0}</div></div>
              </div>

              <div className="grid gap-3 sm:grid-cols-[110px_minmax(0,1fr)]">
                <input
                  className="field"
                  type="number"
                  min="0"
                  value={item.stock_quantity}
                  onChange={(event) => {
                    const value = event.target.value
                    setItems((current) => current.map((row) => (row.id === item.id ? { ...row, stock_quantity: value } : row)))
                  }}
                  onBlur={(event) => updateQuantity(item.id, event.target.value)}
                  disabled={savingId === item.id}
                />
                <div className="flex gap-2">
                  <input
                    className="field max-w-24"
                    type="number"
                    min="0"
                    placeholder="Qty"
                    value={restockAmounts[item.id] ?? ''}
                    onChange={(event) =>
                      setRestockAmounts((current) => ({
                        ...current,
                        [item.id]: event.target.value,
                      }))
                    }
                    disabled={savingId === item.id}
                  />
                  <button
                    type="button"
                    className="btn-secondary flex-1 whitespace-nowrap"
                    onClick={() => addStock(item)}
                    disabled={savingId === item.id || !(Number(restockAmounts[item.id]) > 0)}
                  >
                    {savingId === item.id ? 'Saving...' : 'Add stock'}
                  </button>
                </div>
              </div>
            </div>
          )
        })}
      </div>

      <div className="card hidden p-0 lg:block">
        <div className="table-shell rounded-[28px] border-0">
          <table>
            <thead>
              <tr>
                <th>SKU</th>
                <th>Product</th>
                <th>Fit</th>
                <th>Size</th>
                <th>Location</th>
                <th>Ordered</th>
                <th>Dry cleaned</th>
                <th>Status</th>
                <th>Reserved</th>
                <th>Available</th>
                <th>Stock</th>
                <th>Restock</th>
              </tr>
            </thead>
            <tbody>
              {filteredItems.map((item) => {
                const stock = Number(item.stock_quantity) || 0
                const reserved = Number(item.reserved_quantity) || 0
                const free = Math.max(stock - reserved, 0)
                const isLow = free <= item.reorder_level
                return (
                  <tr key={item.id}>
                    <td>{item.sku}</td>
                    <td>{item.product_type}</td>
                    <td>{item.fit || '—'}</td>
                    <td>{item.size}</td>
                    <td>{item.location || 'Uniform Room'}</td>
                    <td>{Number(item.ordered_quantity) || 0}</td>
                    <td>{Number(item.dry_cleaned_quantity) || 0}</td>
                    <td><Badge tone={isLow ? 'low' : 'healthy'}>{isLow ? 'Low stock' : 'Healthy'}</Badge></td>
                    <td>{reserved}</td>
                    <td>{free}</td>
                    <td>
                      <input
                        className="field max-w-24"
                        type="number"
                        min="0"
                        value={item.stock_quantity}
                        onChange={(event) => {
                          const value = event.target.value
                          setItems((current) => current.map((row) => (row.id === item.id ? { ...row, stock_quantity: value } : row)))
                        }}
                        onBlur={(event) => updateQuantity(item.id, event.target.value)}
                        disabled={savingId === item.id}
                      />
                    </td>
                    <td>
                      <div className="flex min-w-[180px] gap-2">
                        <input
                          className="field max-w-20"
                          type="number"
                          min="0"
                          placeholder="Qty"
                          value={restockAmounts[item.id] ?? ''}
                          onChange={(event) =>
                            setRestockAmounts((current) => ({
                              ...current,
                              [item.id]: event.target.value,
                            }))
                          }
                          disabled={savingId === item.id}
                        />
                        <button
                          type="button"
                          className="btn-secondary whitespace-nowrap"
                          onClick={() => addStock(item)}
                          disabled={savingId === item.id || !(Number(restockAmounts[item.id]) > 0)}
                        >
                          {savingId === item.id ? 'Saving...' : 'Add stock'}
                        </button>
                      </div>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
