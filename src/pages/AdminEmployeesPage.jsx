import { useEffect, useMemo, useState } from 'react'
import Badge from '../components/Badge'
import EmptyState from '../components/EmptyState'
import KpiCard from '../components/KpiCard'
import PageHeader from '../components/PageHeader'
import { supabase } from '../lib/supabase'

const emptyForm = {
  id: '',
  employee_id: '',
  full_name: '',
  ikea_email: '',
  department: '',
  location: 'Toronto',
  is_active: true,
}

const sampleImport = `employee_id,full_name,ikea_email,department,location,is_active
100301,Olivia Pereira,olivia.pereira@ikea.com,Fulfilment Operations,Toronto,true
100302,Bruno Lima,bruno.lima@ikea.com,Sales,Toronto,true
100303,Carla Mendes,carla.mendes@ikea.com,P&C,Toronto,true`

function parseCsv(text) {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => line.split(',').map((item) => item.trim()))
}

export default function AdminEmployeesPage() {
  const [employees, setEmployees] = useState([])
  const [query, setQuery] = useState('')
  const [form, setForm] = useState(emptyForm)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  const [importText, setImportText] = useState(sampleImport)
  const [importing, setImporting] = useState(false)

  async function loadEmployees() {
    if (!supabase) return
    const { data } = await supabase
      .from('employees')
      .select('*')
      .order('full_name')
    setEmployees(data ?? [])
  }

  useEffect(() => {
    loadEmployees()
  }, [])

  const filteredEmployees = useMemo(() => {
    const term = query.trim().toLowerCase()
    return employees.filter((employee) => {
      if (!term) return true
      const haystack = `${employee.employee_id} ${employee.full_name} ${employee.ikea_email} ${employee.department} ${employee.location}`.toLowerCase()
      return haystack.includes(term)
    })
  }, [employees, query])

  const stats = useMemo(() => ({
    total: employees.length,
    active: employees.filter((employee) => employee.is_active).length,
    inactive: employees.filter((employee) => !employee.is_active).length,
    departments: new Set(employees.map((employee) => employee.department).filter(Boolean)).size,
  }), [employees])

  function startEdit(employee) {
    setForm({
      id: employee.id,
      employee_id: employee.employee_id,
      full_name: employee.full_name,
      ikea_email: employee.ikea_email,
      department: employee.department || '',
      location: employee.location || 'Toronto',
      is_active: employee.is_active,
    })
    setMessage('Editing employee record.')
  }

  function resetForm() {
    setForm(emptyForm)
    setMessage('')
  }

  async function handleSubmit(event) {
    event.preventDefault()
    if (!supabase) return
    setSaving(true)
    setMessage('')

    const payload = {
      employee_id: form.employee_id.trim(),
      full_name: form.full_name.trim(),
      ikea_email: form.ikea_email.trim().toLowerCase(),
      department: form.department.trim() || null,
      location: form.location.trim() || 'Toronto',
      is_active: Boolean(form.is_active),
    }

    const query = form.id
      ? supabase.from('employees').update(payload).eq('id', form.id)
      : supabase.from('employees').insert(payload)

    const { error } = await query
    if (error) {
      setMessage(error.message)
      setSaving(false)
      return
    }

    setMessage(form.id ? 'Employee updated successfully.' : 'Employee added successfully.')
    resetForm()
    await loadEmployees()
    setSaving(false)
  }

  async function handleDelete(employee) {
    if (!supabase) return
    const confirmed = window.confirm(`Delete ${employee.full_name}?`)
    if (!confirmed) return

    const { error } = await supabase.from('employees').delete().eq('id', employee.id)
    if (error) {
      setMessage(error.message)
      return
    }

    setMessage('Employee deleted successfully.')
    if (form.id === employee.id) resetForm()
    await loadEmployees()
  }

  async function handleImport() {
    if (!supabase) return
    setImporting(true)
    setMessage('')

    try {
      const rows = parseCsv(importText)
      if (rows.length < 2) {
        throw new Error('Paste at least one employee row below the header.')
      }

      const [header, ...body] = rows
      const expectedHeader = ['employee_id', 'full_name', 'ikea_email', 'department', 'location', 'is_active']

      if (header.join('|').toLowerCase() !== expectedHeader.join('|')) {
        throw new Error('CSV header must be: employee_id,full_name,ikea_email,department,location,is_active')
      }

      const payload = body.map((row, index) => {
        if (row.length < 6) {
          throw new Error(`Row ${index + 2} is incomplete.`)
        }

        return {
          employee_id: row[0],
          full_name: row[1],
          ikea_email: row[2].toLowerCase(),
          department: row[3] || null,
          location: row[4] || 'Toronto',
          is_active: String(row[5]).toLowerCase() !== 'false',
        }
      })

      const { error } = await supabase.from('employees').upsert(payload, { onConflict: 'employee_id' })
      if (error) throw error

      setMessage(`Import completed successfully. ${payload.length} employee record(s) processed.`)
      await loadEmployees()
    } catch (error) {
      setMessage(error.message)
    } finally {
      setImporting(false)
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Workforce"
        title="Employee directory"
        description="Centralize all co-worker records in one place. Request pages now use employee ID lookup and auto-fill name and IKEA email without letting employees edit those fields."
      />

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <KpiCard label="Employees" value={stats.total} helper="Imported and manually maintained co-worker records." accent="blue" />
        <KpiCard label="Active" value={stats.active} helper="Available for QR request lookup." accent="yellow" />
        <KpiCard label="Inactive" value={stats.inactive} helper="Hidden from the request workflow." accent="white" />
        <KpiCard label="Departments" value={stats.departments} helper="Distinct departments represented in the directory." accent="white" />
      </div>

      <div className="grid gap-6 xl:grid-cols-[380px_minmax(0,1fr)]">
        <div className="space-y-6">
          <div className="card p-6">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-xl font-semibold text-ink">Add or edit employee</h2>
                <p className="mt-2 text-sm text-slate-500">Use this section to maintain the employee master list that drives request auto-fill.</p>
              </div>
              <Badge tone="approved">Auto-fill enabled</Badge>
            </div>

            {message ? <div className="mt-4 rounded-2xl bg-slate-50 p-4 text-sm text-slate-700">{message}</div> : null}

            <form className="mt-6 space-y-4" onSubmit={handleSubmit}>
              <div>
                <label className="field-label">Employee ID</label>
                <input className="field" value={form.employee_id} onChange={(event) => setForm((current) => ({ ...current, employee_id: event.target.value }))} placeholder="e.g. 100245" required />
              </div>
              <div>
                <label className="field-label">Full name</label>
                <input className="field" value={form.full_name} onChange={(event) => setForm((current) => ({ ...current, full_name: event.target.value }))} required />
              </div>
              <div>
                <label className="field-label">IKEA email</label>
                <input className="field" type="email" value={form.ikea_email} onChange={(event) => setForm((current) => ({ ...current, ikea_email: event.target.value }))} required />
              </div>
              <div>
                <label className="field-label">Department</label>
                <input className="field" value={form.department} onChange={(event) => setForm((current) => ({ ...current, department: event.target.value }))} placeholder="Fulfilment Operations" />
              </div>
              <div>
                <label className="field-label">Location</label>
                <input className="field" value={form.location} onChange={(event) => setForm((current) => ({ ...current, location: event.target.value }))} placeholder="Toronto" />
              </div>
              <label className="flex items-center gap-3 rounded-2xl border border-slate-200 px-4 py-3 text-sm text-slate-700">
                <input type="checkbox" checked={form.is_active} onChange={(event) => setForm((current) => ({ ...current, is_active: event.target.checked }))} />
                Active employee
              </label>
              <div className="flex gap-3">
                <button className="btn-primary flex-1" disabled={saving} type="submit">{saving ? 'Saving...' : form.id ? 'Update employee' : 'Add employee'}</button>
                <button className="btn-secondary" disabled={saving} onClick={resetForm} type="button">Clear</button>
              </div>
            </form>
          </div>

          <div className="card p-6">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-xl font-semibold text-ink">Simulated employee import</h2>
                <p className="mt-2 text-sm text-slate-500">Paste the employee list you receive and import it into the employees table in one action.</p>
              </div>
              <Badge tone="healthy">CSV</Badge>
            </div>

            <div className="mt-4 rounded-2xl bg-slate-50 p-4 text-xs text-slate-600">
              Header required: employee_id,full_name,ikea_email,department,location,is_active
            </div>

            <textarea
              className="field mt-4 min-h-56"
              value={importText}
              onChange={(event) => setImportText(event.target.value)}
            />

            <button className="btn-primary mt-4 w-full" onClick={handleImport} type="button" disabled={importing}>
              {importing ? 'Importing...' : 'Import employee list'}
            </button>
          </div>
        </div>

        <div className="space-y-6">
          <div className="card p-5">
            <input
              className="field"
              placeholder="Search by employee ID, name, email, department, or location"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
            />
          </div>

          <div className="card p-0">
            {!filteredEmployees.length ? (
              <div className="p-6">
                <EmptyState title="No employees found" description="Load the simulated employee import or create your first employee record here." />
              </div>
            ) : (
              <div className="table-shell rounded-[28px] border-0">
                <table>
                  <thead>
                    <tr>
                      <th>Employee ID</th>
                      <th>Name</th>
                      <th>Department</th>
                      <th>IKEA email</th>
                      <th>Status</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredEmployees.map((employee) => (
                      <tr key={employee.id}>
                        <td className="font-semibold text-ink">{employee.employee_id}</td>
                        <td>
                          <div className="font-semibold text-ink">{employee.full_name}</div>
                          <div className="text-xs text-slate-400">{employee.location || 'Toronto'}</div>
                        </td>
                        <td>{employee.department || '—'}</td>
                        <td>{employee.ikea_email}</td>
                        <td>
                          <Badge tone={employee.is_active ? 'approved' : 'cancelled'}>{employee.is_active ? 'Active' : 'Inactive'}</Badge>
                        </td>
                        <td>
                          <div className="flex gap-2">
                            <button className="btn-secondary px-3 py-2 text-xs" onClick={() => startEdit(employee)} type="button">Edit</button>
                            <button className="btn-ghost px-3 py-2 text-xs text-red-600" onClick={() => handleDelete(employee)} type="button">Delete</button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
