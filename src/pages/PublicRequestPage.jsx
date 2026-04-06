import { useEffect, useMemo, useRef, useState } from 'react'
import Badge from '../components/Badge'
import { supabase, supabaseConfigError } from '../lib/supabase'
import { sendNewRequestEmail } from '../lib/emailApi'
import { formatInventoryLabel, getSizeChartRows, getSizeNote, sortSizes } from '../lib/uniformCatalog'

const initialForm = {
  employee_id: '',
  product_type: '',
  fit: '',
  colour: '',
  requested_size: '',
  notes: '',
}

export default function PublicRequestPage() {
  const [form, setForm] = useState(initialForm)
  const [inventory, setInventory] = useState([])
  const [sizeChart, setSizeChart] = useState([])
  const [employee, setEmployee] = useState(null)
  const [employeeLookupState, setEmployeeLookupState] = useState('idle')
  const [submitting, setSubmitting] = useState(false)
  const [result, setResult] = useState(null)
  const [error, setError] = useState('')
  const lookupTokenRef = useRef(0)

  useEffect(() => {
    async function loadInventory() {
      if (!supabase) return
      const [{ data: inventoryData, error: loadError }, { data: sizeData }] = await Promise.all([
        supabase
          .from('inventory_items')
          .select('id, product_type, colour, fit, style, size, stock_quantity, reserved_quantity, is_active, location')
          .eq('is_active', true)
          .order('product_type')
          .order('fit')
          .order('size'),
        supabase.from('uniform_size_chart').select('*').order('sort_order'),
      ])

      if (loadError) {
        setError(loadError.message)
        return
      }
      setInventory(inventoryData ?? [])
      setSizeChart(sizeData ?? [])
    }

    loadInventory()
  }, [])

  const inventoryWithFreeUnits = useMemo(() => {
    return inventory.map((item) => ({
      ...item,
      free_units: Math.max((item.stock_quantity || 0) - (item.reserved_quantity || 0), 0),
    }))
  }, [inventory])

  const selectableInventory = useMemo(() => {
    return inventoryWithFreeUnits.filter((item) => item.free_units > 0)
  }, [inventoryWithFreeUnits])

  const productTypes = useMemo(() => {
    return [...new Set(selectableInventory.map((item) => item.product_type).filter(Boolean))]
  }, [selectableInventory])

  const fits = useMemo(() => {
    return [...new Set(
      selectableInventory
        .filter((item) => !form.product_type || item.product_type === form.product_type)
        .map((item) => item.fit)
        .filter(Boolean)
    )]
  }, [selectableInventory, form.product_type])

  const colours = useMemo(() => {
    return [...new Set(
      selectableInventory
        .filter((item) =>
          (!form.product_type || item.product_type === form.product_type) &&
          (!form.fit || item.fit === form.fit)
        )
        .map((item) => item.colour)
        .filter((value) => value && value !== 'Standard')
    )]
  }, [selectableInventory, form.product_type, form.fit])

  const shouldShowColour = colours.length > 0

  const allSizeRows = useMemo(() => {
    return inventoryWithFreeUnits
      .filter((item) =>
        (!form.product_type || item.product_type === form.product_type) &&
        (!form.fit || item.fit === form.fit) &&
        (!shouldShowColour || !form.colour || item.colour === form.colour)
      )
      .sort((a, b) => sortSizes(a.size, b.size))
  }, [inventoryWithFreeUnits, form.product_type, form.fit, form.colour, shouldShowColour])

  const sizeRows = useMemo(() => {
    return allSizeRows.filter((item) => item.free_units > 0)
  }, [allSizeRows])

  const exactAvailability = useMemo(() => {
    return sizeRows.find((item) => item.size === form.requested_size) || null
  }, [sizeRows, form.requested_size])

  const sizeGuideRows = useMemo(() => {
    return getSizeChartRows(sizeChart, form.product_type, form.fit)
  }, [sizeChart, form.product_type, form.fit])

  async function lookupEmployee(employeeId) {
    const cleanId = employeeId.trim()

    if (!supabase || !cleanId) {
      setEmployee(null)
      setEmployeeLookupState('idle')
      return
    }

    const token = ++lookupTokenRef.current
    setEmployeeLookupState('loading')
    setError('')

    try {
      const { data, error: lookupError } = await supabase.rpc('lookup_employee_by_id', {
        p_employee_id: cleanId,
      })

      if (token !== lookupTokenRef.current) return

      if (lookupError) {
        setEmployee(null)
        setEmployeeLookupState('error')
        setError(lookupError.message)
        return
      }

      if (!data) {
        setEmployee(null)
        setEmployeeLookupState('not_found')
        setError('Employee ID not found. Please contact an admin to be added to the employee directory.')
        return
      }

      setEmployee(data)
      setEmployeeLookupState('ready')
      setError('')
    } catch (lookupError) {
      if (token !== lookupTokenRef.current) return
      setEmployee(null)
      setEmployeeLookupState('error')
      setError(lookupError?.message || 'Could not look up this employee ID right now.')
    }
  }

  function updateField(event) {
    const { name, value } = event.target
    setResult(null)
    setError('')

    setForm((current) => ({
      ...current,
      [name]: value,
      ...(name === 'product_type' ? { fit: '', colour: '', requested_size: '' } : {}),
      ...(name === 'fit' ? { colour: '', requested_size: '' } : {}),
      ...(name === 'colour' ? { requested_size: '' } : {}),
    }))

    if (name === 'employee_id') {
      lookupTokenRef.current += 1
      setEmployee(null)
      setEmployeeLookupState('idle')
    }
  }

  async function handleEmployeeLookup(event) {
    event?.preventDefault?.()
    if (employeeLookupState === 'loading') return
    await lookupEmployee(form.employee_id)
  }

  async function handleSubmit(event) {
    event.preventDefault()
    setSubmitting(true)
    setError('')
    setResult(null)

    if (!supabase) {
      setError(supabaseConfigError || 'Supabase is not configured')
      setSubmitting(false)
      return
    }

    if (!employee?.employee_id) {
      setError('Search and confirm a valid employee ID before sending the request.')
      setSubmitting(false)
      return
    }

    if (!exactAvailability?.id) {
      setError('Select a valid in-stock product, fit, and size before sending the request.')
      setSubmitting(false)
      return
    }

    const { data, error: rpcError } = await supabase.rpc('submit_uniform_request', {
      p_employee_id: employee.employee_id,
      p_inventory_item_id: exactAvailability.id,
      p_notes: form.notes || null,
      p_quantity: 1,
    })

    if (rpcError) {
      setError(rpcError.message)
      setSubmitting(false)
      return
    }

    try {
      await sendNewRequestEmail({
        ...data,
        employee_name: employee.full_name,
        employee_email: employee.ikea_email,
        product_type: exactAvailability.product_type,
        fit: exactAvailability.fit,
        colour: exactAvailability.colour,
        requested_size: exactAvailability.size,
        notes: form.notes || null,
      })
    } catch (emailError) {
      console.error('Failed to send request email:', emailError)
    }

    setResult(data)
    setForm(initialForm)
    setEmployee(null)
    setEmployeeLookupState('idle')
    setSubmitting(false)
  }

  const freeUnits = exactAvailability?.free_units || 0

  return (
    <div className="min-h-screen px-4 py-4 sm:px-6 sm:py-6">
      <div className="mx-auto max-w-6xl space-y-6">
        <section className="overflow-hidden rounded-[32px] bg-gradient-to-br from-[#0058A3] via-[#0A7BD8] to-[#004987] text-white shadow-soft">
          <div className="grid gap-6 px-5 py-8 sm:px-8 lg:grid-cols-[minmax(0,1fr)_320px] lg:items-end">
            <div>
              <div className="inline-flex rounded-full bg-[#FFDA1A] px-3 py-1 text-xs font-bold uppercase tracking-[0.25em] text-slate-900">QR request page</div>
              <h1 className="mt-4 text-3xl font-bold sm:text-4xl">Request your uniform</h1>
              <p className="mt-3 max-w-2xl text-sm text-blue-100 sm:text-base">
                Enter your employee ID to auto-fill your IKEA profile, then choose the exact product, fit, and IKEA size code that still has inventory available.
              </p>
            </div>
            <div className="grid gap-3 rounded-[28px] bg-white/10 p-4 backdrop-blur sm:grid-cols-3 lg:grid-cols-1">
              <div>
                <div className="text-xs uppercase tracking-[0.24em] text-blue-100">Step 1</div>
                <div className="mt-2 font-semibold">Enter employee ID</div>
              </div>
              <div>
                <div className="text-xs uppercase tracking-[0.24em] text-blue-100">Step 2</div>
                <div className="mt-2 font-semibold">Choose only from in-stock sizes</div>
              </div>
              <div>
                <div className="text-xs uppercase tracking-[0.24em] text-blue-100">Step 3</div>
                <div className="mt-2 font-semibold">Submit request</div>
              </div>
            </div>
          </div>
        </section>

        <div className="grid gap-6 lg:grid-cols-[minmax(0,1.15fr)_360px]">
          <div className="card overflow-hidden">
            <div className="border-b border-slate-100 px-5 py-5 sm:px-8">
              <h2 className="text-xl font-semibold text-ink">Employee request form</h2>
              <p className="mt-1 text-sm text-slate-500">The employee directory auto-fills the co-worker name and IKEA email before the request is sent. Size options in the dropdown are limited to rows with free inventory count.</p>
            </div>

            <div className="p-5 sm:p-8">
              {error ? <div className="mb-4 rounded-2xl bg-red-50 p-4 text-sm text-red-700">{error}</div> : null}
              {result ? (
                <div className="mb-5 rounded-2xl bg-emerald-50 p-4 text-sm text-emerald-800">
                  Request submitted successfully. Current status: <strong>{result.status}</strong>. Mode: <strong>{result.fulfillment_mode}</strong>.
                </div>
              ) : null}

              <form className="grid gap-4 md:grid-cols-2" onSubmit={handleSubmit}>
                <div className="md:col-span-2">
                  <label className="field-label">Employee ID</label>
                  <div className="flex flex-col gap-3 sm:flex-row">
                    <input
                      className="field"
                      name="employee_id"
                      value={form.employee_id}
                      onChange={updateField}
                      placeholder="Enter your employee ID"
                      required
                    />
                    <button
                      type="button"
                      className="btn-secondary whitespace-nowrap sm:min-w-[140px]"
                      onClick={handleEmployeeLookup}
                      disabled={!form.employee_id.trim() || employeeLookupState === 'loading'}
                    >
                      {employeeLookupState === 'loading' ? 'Searching...' : 'Search ID'}
                    </button>
                  </div>
                  <div className="mt-2 text-xs text-slate-500">
                    {employeeLookupState === 'loading'
                      ? 'Looking up employee...'
                      : employeeLookupState === 'ready'
                        ? 'Employee found and locked for this request.'
                        : employeeLookupState === 'error' || employeeLookupState === 'not_found'
                          ? 'We could not match this employee ID yet.'
                          : 'Search your employee ID to auto-fill your name and IKEA email.'}
                  </div>
                </div>

                <div>
                  <label className="field-label">Full name</label>
                  <input className="field bg-slate-50" value={employee?.full_name || ''} readOnly placeholder="Auto-filled from employee directory" />
                </div>
                <div>
                  <label className="field-label">IKEA email</label>
                  <input className="field bg-slate-50" value={employee?.ikea_email || ''} readOnly placeholder="Auto-filled from employee directory" />
                </div>

                <div>
                  <label className="field-label">Product</label>
                  <select className="field" name="product_type" value={form.product_type} onChange={updateField} required>
                    <option value="">Select</option>
                    {productTypes.map((value) => <option key={value} value={value}>{value}</option>)}
                  </select>
                </div>
                <div>
                  <label className="field-label">Fit</label>
                  <select className="field" name="fit" value={form.fit} onChange={updateField} required>
                    <option value="">Select</option>
                    {fits.map((value) => <option key={value} value={value}>{value}</option>)}
                  </select>
                </div>
                {shouldShowColour ? (
                  <div>
                    <label className="field-label">Colour</label>
                    <select className="field" name="colour" value={form.colour} onChange={updateField} required={shouldShowColour}>
                      <option value="">Select</option>
                      {colours.map((value) => <option key={value} value={value}>{value}</option>)}
                    </select>
                  </div>
                ) : null}
                <div className={shouldShowColour ? '' : 'md:col-span-2'}>
                  <label className="field-label">IKEA size code</label>
                  <select className="field" name="requested_size" value={form.requested_size} onChange={updateField} required>
                    <option value="">Select</option>
                    {sizeRows.map((item) => <option key={item.id} value={item.size}>{`${item.size} (${item.free_units} available)`}</option>)}
                  </select>
                  <div className="mt-2 text-xs text-slate-500">Only sizes with free units in inventory count are shown here.</div>
                </div>

                <div className="md:col-span-2">
                  <label className="field-label">Notes</label>
                  <textarea className="field min-h-28" name="notes" value={form.notes} onChange={updateField} placeholder="Special instructions or extra context" />
                </div>
                <div className="md:col-span-2 sticky bottom-3 z-10 pt-2">
                  <button className="btn-primary w-full" disabled={submitting || !form.requested_size || !employee} type="submit">
                    {submitting ? 'Submitting...' : 'Send request'}
                  </button>
                </div>
              </form>
            </div>
          </div>

          <div className="space-y-6">
            <div className="card p-6">
              <h2 className="text-lg font-semibold text-ink">Selected inventory row</h2>
              <p className="mt-2 text-sm text-slate-500">The request uses the exact inventory item you selected below.</p>
              <div className="mt-4 rounded-[24px] bg-slate-50 p-4 text-sm">
                {!form.requested_size ? (
                  <div className="text-slate-500">Select a product, fit, and size code to preview inventory.</div>
                ) : exactAvailability ? (
                  <div className="space-y-4">
                    <div className="rounded-2xl bg-white p-4">
                      <div className="font-semibold text-ink">{formatInventoryLabel(exactAvailability)}</div>
                      <div className="mt-1 text-xs text-slate-500">{exactAvailability.location || 'Uniform Room'}{shouldShowColour ? ` · ${exactAvailability.colour}` : ''}</div>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <Badge tone={freeUnits <= 0 ? 'rejected' : freeUnits <= 3 ? 'pending' : 'approved'}>
                        {freeUnits <= 0 ? 'Out of stock' : freeUnits <= 3 ? `Low stock: ${freeUnits}` : `Available: ${freeUnits}`}
                      </Badge>
                    </div>
                    <div className="grid gap-3 sm:grid-cols-2">
                      <div className="rounded-2xl bg-white p-4">
                        <div className="text-xs uppercase tracking-wide text-slate-500">Stock</div>
                        <div className="mt-2 text-2xl font-bold text-ink">{exactAvailability.stock_quantity}</div>
                      </div>
                      <div className="rounded-2xl bg-white p-4">
                        <div className="text-xs uppercase tracking-wide text-slate-500">Reserved</div>
                        <div className="mt-2 text-2xl font-bold text-ink">{exactAvailability.reserved_quantity}</div>
                      </div>
                    </div>
                  </div>
                ) : (
                  <div className="text-slate-500">No exact stock row found for that combination yet.</div>
                )}
              </div>
            </div>

            <div className="card p-6">
              <h2 className="text-lg font-semibold text-ink">Available size codes</h2>
              <div className="mt-4 space-y-3 text-sm">
                {allSizeRows.length ? allSizeRows.map((item) => {
                  const available = item.free_units
                  return (
                    <label key={item.id} className={`block rounded-[24px] border p-4 transition ${form.requested_size === item.size ? 'border-ikeaBlue bg-blue-50' : 'border-slate-200 bg-white'}`}>
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <div className="font-semibold text-ink">{item.size}</div>
                          <div className="text-xs text-slate-500">Stock {item.stock_quantity} · Reserved {item.reserved_quantity}</div>
                        </div>
                        <Badge tone={available <= 0 ? 'rejected' : available <= 3 ? 'pending' : 'approved'}>
                          {available <= 0 ? 'Out of stock' : available <= 3 ? `Low stock: ${available}` : `Available: ${available}`}
                        </Badge>
                      </div>
                    </label>
                  )
                }) : <div className="rounded-2xl bg-slate-50 p-4 text-slate-500">Select a product and fit to load the available IKEA size codes.</div>}
                {form.product_type && form.fit && !sizeRows.length ? (
                  <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-slate-600">
                    There is no free stock for this product and fit right now. Ask an admin to restock or choose a different product.
                  </div>
                ) : null}
              </div>
            </div>

            <div className="card p-6">
              <h2 className="text-lg font-semibold text-ink">IKEA size chart</h2>
              <p className="mt-2 text-sm text-slate-500">Reference based on the IKEA size chart PDF for the selected product and fit.</p>
              <div className="mt-4 space-y-3 text-sm">
                {sizeGuideRows.length ? sizeGuideRows.map((row) => (
                  <div key={row.id} className="rounded-[24px] border border-slate-200 p-4">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="font-semibold text-ink">{row.size_label}</div>
                        <div className="text-xs text-slate-500">{getSizeNote(row) || 'Reference size code'}</div>
                      </div>
                      <Badge tone="healthy">{row.category.replaceAll('_', ' ')}</Badge>
                    </div>
                  </div>
                )) : (
                  <div className="rounded-2xl bg-slate-50 p-4 text-slate-500">Choose a product and fit to load the matching IKEA size reference.</div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
