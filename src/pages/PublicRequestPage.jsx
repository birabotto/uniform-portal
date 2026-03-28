import { useEffect, useMemo, useState } from 'react'
import { Button, Card, Input, Select, Textarea } from '../components/ui'
import { getEmployeeByEmployeeId, getPublicRequestData, submitUniformRequest } from '../lib/portalApi'

const initialForm = {
  employee_id: '',
  employee_name: '',
  employee_email: '',
  department: '',
  product_type: '',
  style: '',
  colour: '',
  fit: '',
  sleeve: '',
  requested_size: '',
  suggested_size: '',
  special_request_note: '',
}

function uniqueValues(items, field, filters = {}) {
  return [...new Set(
    items
      .filter((item) => Object.entries(filters).every(([key, value]) => !value || (item[key] || '') === value))
      .map((item) => item[field])
      .filter(Boolean)
  )]
}

export default function PublicRequestPage() {
  const [form, setForm] = useState(initialForm)
  const [inventory, setInventory] = useState([])
  const [inventoryLoading, setInventoryLoading] = useState(true)
  const [lookupState, setLookupState] = useState({ status: 'idle', message: '' })
  const [submitting, setSubmitting] = useState(false)
  const [feedback, setFeedback] = useState({ type: '', message: '' })

  useEffect(() => {
    let ignore = false

    async function loadInventory() {
      try {
        const data = await getPublicRequestData()
        if (!ignore) {
          setInventory(data)
        }
      } catch (error) {
        if (!ignore) {
          setFeedback({ type: 'error', message: error.message || 'Unable to load inventory options.' })
        }
      } finally {
        if (!ignore) {
          setInventoryLoading(false)
        }
      }
    }

    loadInventory()
    return () => {
      ignore = true
    }
  }, [])

  useEffect(() => {
    const id = form.employee_id.trim()

    if (!id) {
      setLookupState({ status: 'idle', message: '' })
      setForm((current) => {
        if (!current.employee_name && !current.employee_email && !current.department) return current
        return { ...current, employee_name: '', employee_email: '', department: '' }
      })
      return
    }

    if (id.length < 3) {
      setLookupState({ status: 'typing', message: 'Keep typing the employee ID...' })
      return
    }

    const timeout = setTimeout(async () => {
      try {
        setLookupState({ status: 'loading', message: 'Finding employee...' })
        const employee = await getEmployeeByEmployeeId(id)

        if (!employee) {
          setLookupState({ status: 'error', message: 'Employee not found. Please contact an admin.' })
          setForm((current) => ({ ...current, employee_name: '', employee_email: '', department: '' }))
          return
        }

        setForm((current) => ({
          ...current,
          employee_id: employee.employee_id,
          employee_name: employee.full_name,
          employee_email: employee.email,
          department: employee.department || '',
        }))
        setLookupState({ status: 'success', message: 'Employee found. Name, email, and department were auto-filled.' })
      } catch (error) {
        setLookupState({ status: 'error', message: error.message || 'Unable to find employee.' })
      }
    }, 450)

    return () => clearTimeout(timeout)
  }, [form.employee_id])

  const productTypes = useMemo(() => uniqueValues(inventory, 'product_type'), [inventory])
  const styles = useMemo(() => uniqueValues(inventory, 'style', { product_type: form.product_type }), [inventory, form.product_type])
  const colours = useMemo(
    () => uniqueValues(inventory, 'colour', { product_type: form.product_type, style: form.style }),
    [inventory, form.product_type, form.style]
  )
  const sizes = useMemo(
    () => uniqueValues(inventory, 'size', { product_type: form.product_type, style: form.style, colour: form.colour }),
    [inventory, form.product_type, form.style, form.colour]
  )

  const availability = useMemo(() => {
    return inventory.find((item) =>
      item.product_type === form.product_type &&
      (item.style || '') === (form.style || '') &&
      (item.colour || '') === (form.colour || '') &&
      item.size === form.requested_size
    )
  }, [inventory, form])

  const canSubmit = useMemo(() => {
    return Boolean(
      form.employee_id &&
      form.employee_name &&
      form.employee_email &&
      form.product_type &&
      form.style &&
      form.colour &&
      form.requested_size &&
      lookupState.status === 'success'
    )
  }, [form, lookupState.status])

  async function handleSubmit(event) {
    event.preventDefault()
    setSubmitting(true)
    setFeedback({ type: '', message: '' })

    try {
      await submitUniformRequest(form)
      setFeedback({ type: 'success', message: 'Your request was sent successfully.' })
      setForm(initialForm)
      setLookupState({ status: 'idle', message: '' })
    } catch (error) {
      setFeedback({ type: 'error', message: error.message || 'Unable to submit request.' })
    } finally {
      setSubmitting(false)
    }
  }

  function updateField(field, value) {
    setForm((current) => {
      const next = { ...current, [field]: value }

      if (field === 'product_type') {
        next.style = ''
        next.colour = ''
        next.requested_size = ''
      }

      if (field === 'style') {
        next.colour = ''
        next.requested_size = ''
      }

      if (field === 'colour') {
        next.requested_size = ''
      }

      return next
    })
  }

  const lookupTone = {
    idle: 'border-softBorder bg-white text-slate-500',
    typing: 'border-softBorder bg-softBg text-slate-600',
    loading: 'border-blue-200 bg-blue-50 text-ikeaBlue',
    success: 'border-emerald-200 bg-emerald-50 text-emerald-700',
    error: 'border-red-200 bg-red-50 text-red-700',
  }[lookupState.status || 'idle']

  return (
    <div className="min-h-screen bg-[#eef2f6] px-4 py-5 md:px-6 lg:px-8">
      <div className="mx-auto max-w-[1180px]">
        <section className="rounded-[34px] bg-gradient-to-r from-[#2d63b1] to-[#1f5299] px-8 py-8 text-white shadow-[0_24px_60px_rgba(8,59,112,0.14)] md:px-10 md:py-9">
          <div className="grid gap-6 lg:grid-cols-[1fr_320px] lg:items-start">
            <div>
              <div className="inline-flex rounded-full bg-ikeaYellow px-4 py-2 text-xs font-extrabold uppercase tracking-[0.32em] text-black">
                QR request page
              </div>
              <h1 className="mt-5 text-4xl font-extrabold leading-tight md:text-5xl">Request your uniform</h1>
              <p className="mt-4 max-w-[760px] text-lg leading-8 text-blue-50/95">
                Pick the item, style, colour, and size you need. If stock is available, the system reserves it while your request stays pending. If not, it tries the next size up or creates a special request.
              </p>
            </div>

            <div className="rounded-[28px] bg-white/10 p-6 backdrop-blur-sm">
              {[['Step 1', 'Choose your item'], ['Step 2', 'Preview live availability'], ['Step 3', 'Submit request']].map(([step, text]) => (
                <div key={step} className="mb-5 last:mb-0">
                  <p className="text-xs font-medium uppercase tracking-[0.3em] text-blue-100">{step}</p>
                  <p className="mt-2 text-[1.15rem] font-bold text-white">{text}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_360px]">
          <Card title="Employee request form" subtitle="Mobile-first form designed for QR code access." className="overflow-hidden p-0">
            <form className="space-y-5 px-8 py-7" onSubmit={handleSubmit}>
              {feedback.message ? (
                <div className={`rounded-[20px] border px-5 py-4 text-sm ${feedback.type === 'success' ? 'border-emerald-200 bg-emerald-50 text-emerald-700' : 'border-red-200 bg-red-50 text-red-700'}`}>
                  {feedback.message}
                </div>
              ) : null}

              <div className="grid gap-4 md:grid-cols-2">
                <div className="md:col-span-2">
                  <Input
                    label="Employee ID"
                    value={form.employee_id}
                    onChange={(event) => updateField('employee_id', event.target.value)}
                    placeholder="Enter your IKEA employee ID"
                    inputMode="numeric"
                    className="h-[54px] rounded-[18px]"
                  />
                </div>

                <div className={`md:col-span-2 rounded-[20px] border px-5 py-4 text-sm ${lookupTone}`}>
                  {lookupState.message || 'Enter your employee ID to auto-fill your details.'}
                </div>

                <Input label="Full name" value={form.employee_name} readOnly placeholder="Auto-filled after employee ID lookup" className="h-[54px] rounded-[18px] bg-[#f8fafc]" />
                <Input label="Email" value={form.employee_email} readOnly placeholder="Auto-filled after employee ID lookup" className="h-[54px] rounded-[18px] bg-[#f8fafc]" />
                <Input label="Department" value={form.department} readOnly placeholder="Auto-filled department" className="h-[54px] rounded-[18px] bg-[#f8fafc] md:col-span-2" />

                <Select label="Product type" value={form.product_type} onChange={(event) => updateField('product_type', event.target.value)} className="h-[54px] rounded-[18px]">
                  <option value="">Select</option>
                  {productTypes.map((value) => <option key={value} value={value}>{value}</option>)}
                </Select>
                <Select label="Style" value={form.style} onChange={(event) => updateField('style', event.target.value)} className="h-[54px] rounded-[18px]" disabled={!form.product_type || inventoryLoading}>
                  <option value="">Select</option>
                  {styles.map((value) => <option key={value} value={value}>{value}</option>)}
                </Select>
                <Select label="Colour" value={form.colour} onChange={(event) => updateField('colour', event.target.value)} className="h-[54px] rounded-[18px]" disabled={!form.style || inventoryLoading}>
                  <option value="">Select</option>
                  {colours.map((value) => <option key={value} value={value}>{value}</option>)}
                </Select>
                <Select label="Size" value={form.requested_size} onChange={(event) => updateField('requested_size', event.target.value)} className="h-[54px] rounded-[18px]" disabled={!form.colour || inventoryLoading}>
                  <option value="">Select</option>
                  {sizes.map((value) => <option key={value} value={value}>{value}</option>)}
                </Select>
              </div>

              <Textarea
                label="Notes"
                value={form.special_request_note}
                onChange={(event) => updateField('special_request_note', event.target.value)}
                placeholder="Special instructions or extra context"
                className="rounded-[18px]"
              />

              <div className="sticky bottom-4 z-10 rounded-[24px] bg-white/95 p-2 shadow-[0_14px_36px_rgba(15,23,42,0.12)] backdrop-blur md:static md:bg-transparent md:p-0 md:shadow-none">
                <Button type="submit" disabled={!canSubmit || submitting} className="h-[56px] w-full rounded-[18px] text-base font-bold">
                  {submitting ? 'Submitting...' : 'Submit request'}
                </Button>
              </div>
            </form>
          </Card>

          <div className="space-y-6">
            <Card title="Live availability" subtitle="Preview the exact selected combination before submitting.">
              <div className="rounded-[20px] bg-[#f5f7fb] px-5 py-4 text-sm leading-7 text-slate-600">
                {!form.product_type || !form.style || !form.colour || !form.requested_size ? (
                  'Choose product type, style, colour, and size to preview availability.'
                ) : availability ? (
                  <>
                    <p className="font-semibold text-slate-900">{availability.product_type} • {availability.size}</p>
                    <p className="mt-2">{availability.style || 'Standard'} • {availability.colour || 'Default'}</p>
                    <p className={`mt-3 font-semibold ${availability.stock_quantity > 0 ? 'text-emerald-700' : 'text-red-700'}`}>
                      {availability.stock_quantity > 0 ? `${availability.stock_quantity} unit(s) currently available.` : 'No stock available right now.'}
                    </p>
                  </>
                ) : (
                  'This combination is not in the active inventory yet.'
                )}
              </div>
            </Card>

            <Card title="How the workflow works">
              <ol className="space-y-4 pl-5 text-[15px] leading-7 text-slate-600 marker:text-slate-800">
                <li>Pending requests reserve available stock immediately.</li>
                <li>Approved or ordered requests keep the reservation.</li>
                <li>Rejected or cancelled requests release reserved stock.</li>
                <li>Fulfilled requests reduce stock and close the request.</li>
              </ol>
            </Card>
          </div>
        </div>
      </div>
    </div>
  )
}
