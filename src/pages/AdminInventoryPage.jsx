import { useEffect, useMemo, useState } from 'react'
import { Badge, Button, Card, Input, PageHeader } from '../components/ui'
import { getInventory, saveInventoryItem } from '../lib/portalApi'

const emptyForm = {
  id: '',
  sku: '',
  product_type: '',
  style: '',
  colour: '',
  fit: '',
  sleeve: '',
  size: '',
  stock_quantity: 0,
  reorder_level: 5,
  is_active: true,
}

export default function AdminInventoryPage() {
  const [inventory, setInventory] = useState([])
  const [form, setForm] = useState(emptyForm)
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  async function loadInventory() {
    try {
      setLoading(true)
      const data = await getInventory()
      setInventory(data)
      setError('')
    } catch (error) {
      setError(error.message || 'Unable to load inventory.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadInventory()
  }, [])

  const filteredInventory = useMemo(() => {
    const query = search.trim().toLowerCase()
    if (!query) return inventory

    return inventory.filter((item) =>
      [item.sku, item.product_type, item.style, item.colour, item.size]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(query)
    )
  }, [inventory, search])

  async function handleSubmit(event) {
    event.preventDefault()
    setSaving(true)
    setError('')

    try {
      await saveInventoryItem(form)
      setForm(emptyForm)
      await loadInventory()
    } catch (error) {
      setError(error.message || 'Unable to save inventory item.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
      <PageHeader title="Inventory" description="Manage stock, reorder levels, and active items used by the request flow." />

      {error ? <div className="rounded-3xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div> : null}

      <div className="grid gap-6 xl:grid-cols-[0.95fr_1.05fr]">
        <Card title={form.id ? 'Edit inventory item' : 'Add inventory item'}>
          <form className="grid gap-4 md:grid-cols-2" onSubmit={handleSubmit}>
            <Input label="SKU" value={form.sku} onChange={(event) => setForm((current) => ({ ...current, sku: event.target.value }))} />
            <Input label="Product type" value={form.product_type} onChange={(event) => setForm((current) => ({ ...current, product_type: event.target.value }))} />
            <Input label="Style" value={form.style} onChange={(event) => setForm((current) => ({ ...current, style: event.target.value }))} />
            <Input label="Colour" value={form.colour} onChange={(event) => setForm((current) => ({ ...current, colour: event.target.value }))} />
            <Input label="Fit" value={form.fit} onChange={(event) => setForm((current) => ({ ...current, fit: event.target.value }))} />
            <Input label="Sleeve" value={form.sleeve} onChange={(event) => setForm((current) => ({ ...current, sleeve: event.target.value }))} />
            <Input label="Size" value={form.size} onChange={(event) => setForm((current) => ({ ...current, size: event.target.value }))} />
            <Input
              label="Stock quantity"
              type="number"
              value={form.stock_quantity}
              onChange={(event) => setForm((current) => ({ ...current, stock_quantity: event.target.value }))}
            />
            <Input
              label="Reorder level"
              type="number"
              value={form.reorder_level}
              onChange={(event) => setForm((current) => ({ ...current, reorder_level: event.target.value }))}
            />

            <label className="flex items-center gap-3 rounded-2xl border border-softBorder px-4 py-3">
              <input
                type="checkbox"
                checked={form.is_active}
                onChange={(event) => setForm((current) => ({ ...current, is_active: event.target.checked }))}
              />
              <span className="text-sm font-semibold text-slate-700">Active item</span>
            </label>

            <div className="md:col-span-2 flex flex-wrap gap-3">
              <Button type="submit" disabled={saving}>{saving ? 'Saving...' : form.id ? 'Update item' : 'Create item'}</Button>
              <Button type="button" variant="ghost" onClick={() => setForm(emptyForm)}>Clear</Button>
            </div>
          </form>
        </Card>

        <Card title="Inventory list" subtitle="Search by SKU, item, colour, or size.">
          <Input label="Search" placeholder="Search inventory..." value={search} onChange={(event) => setSearch(event.target.value)} />

          <div className="mt-4 space-y-3">
            {loading ? <div className="rounded-2xl border border-softBorder p-4 text-sm text-slate-500">Loading inventory...</div> : null}

            {!loading && filteredInventory.map((item) => (
              <div key={item.id} className="rounded-2xl border border-softBorder p-4">
                <div className="flex flex-col gap-3 md:flex-row md:justify-between">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-semibold text-slate-900">{item.product_type} • {item.size}</p>
                      <Badge tone={item.stock_quantity <= item.reorder_level ? 'pending' : 'active'}>
                        Stock {item.stock_quantity}
                      </Badge>
                    </div>
                    <p className="mt-1 text-sm text-slate-600">{item.style || 'Standard'} • {item.colour || 'Default'} • SKU {item.sku || '—'}</p>
                    <p className="mt-1 text-sm text-slate-500">Reorder level: {item.reorder_level}</p>
                  </div>

                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() => setForm({
                      id: item.id,
                      sku: item.sku || '',
                      product_type: item.product_type || '',
                      style: item.style || '',
                      colour: item.colour || '',
                      fit: item.fit || '',
                      sleeve: item.sleeve || '',
                      size: item.size || '',
                      stock_quantity: item.stock_quantity ?? 0,
                      reorder_level: item.reorder_level ?? 5,
                      is_active: item.is_active ?? true,
                    })}
                  >
                    Edit
                  </Button>
                </div>
              </div>
            ))}

            {!loading && !filteredInventory.length ? (
              <div className="rounded-2xl border border-dashed border-softBorder p-4 text-sm text-slate-500">No inventory items found.</div>
            ) : null}
          </div>
        </Card>
      </div>
    </>
  )
}
