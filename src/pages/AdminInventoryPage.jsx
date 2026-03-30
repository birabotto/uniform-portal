import { useEffect, useMemo, useState } from 'react'
import Badge from '../components/Badge'
import EmptyState from '../components/EmptyState'
import PageHeader from '../components/PageHeader'
import { supabase } from '../lib/supabase'

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
        .order('style')
        .order('colour')
        .order('size')
      setItems(data ?? [])
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
    return items.filter((item) => {
      const text = `${item.sku} ${item.product_type} ${item.colour} ${item.style} ${item.size}`.toLowerCase()
      return !query || text.includes(query.toLowerCase())
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
        description="Edit absolute stock counts or use Restock to add more units without doing the math yourself. Available units are calculated automatically from stock minus reserved."
      />

      {message ? <div className="card p-4 text-sm text-slate-700">{message}</div> : null}

      <div className="card p-5 space-y-4">
        <input
          className="field"
          placeholder="Search by SKU, product type, colour, style or size"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <div className="rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-600">
          Example: if stock is 8 and you receive 10 more, enter <strong>10</strong> in Restock and the system updates the item to <strong>18</strong> automatically.
        </div>
      </div>

      <div className="card p-0">
        <div className="table-shell rounded-[28px] border-0">
          <table>
            <thead>
              <tr>
                <th>SKU</th>
                <th>Product</th>
                <th>Colour</th>
                <th>Style</th>
                <th>Size</th>
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
                    <td>{item.colour}</td>
                    <td>{item.style}</td>
                    <td>{item.size}</td>
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
