import { useEffect, useMemo, useState } from 'react'
import { Badge, Button, Card, Input, PageHeader } from '../components/ui'
import { deleteEmployee, getEmployees, upsertEmployee } from '../lib/portalApi'

const emptyForm = {
  id: '',
  employee_id: '',
  full_name: '',
  email: '',
  department: '',
  is_active: true,
}

export default function AdminEmployeesPage() {
  const [employees, setEmployees] = useState([])
  const [form, setForm] = useState(emptyForm)
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  async function loadEmployees() {
    try {
      setLoading(true)
      const data = await getEmployees()
      setEmployees(data)
      setError('')
    } catch (error) {
      setError(error.message || 'Unable to load employees.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadEmployees()
  }, [])

  const filteredEmployees = useMemo(() => {
    const query = search.trim().toLowerCase()
    if (!query) return employees

    return employees.filter((employee) =>
      [employee.employee_id, employee.full_name, employee.email, employee.department]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(query)
    )
  }, [employees, search])

  async function handleSubmit(event) {
    event.preventDefault()
    setSaving(true)
    setError('')

    try {
      await upsertEmployee(form)
      setForm(emptyForm)
      await loadEmployees()
    } catch (error) {
      setError(error.message || 'Unable to save employee.')
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(id) {
    if (!window.confirm('Delete this employee record?')) return

    try {
      await deleteEmployee(id)
      await loadEmployees()
      if (form.id === id) setForm(emptyForm)
    } catch (error) {
      setError(error.message || 'Unable to delete employee.')
    }
  }

  return (
    <>
      <PageHeader title="Employee directory" description="Centralized list of co-workers with admin add, edit, and delete controls. Public requests auto-fill based on employee ID." />

      {error ? <div className="rounded-3xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div> : null}

      <div className="grid gap-6 xl:grid-cols-[0.95fr_1.05fr]">
        <Card title={form.id ? 'Edit employee' : 'Add employee'}>
          <form className="space-y-4" onSubmit={handleSubmit}>
            <Input label="Employee ID" value={form.employee_id} onChange={(event) => setForm((current) => ({ ...current, employee_id: event.target.value }))} />
            <Input label="Full name" value={form.full_name} onChange={(event) => setForm((current) => ({ ...current, full_name: event.target.value }))} />
            <Input label="Email" type="email" value={form.email} onChange={(event) => setForm((current) => ({ ...current, email: event.target.value }))} />
            <Input label="Department" value={form.department} onChange={(event) => setForm((current) => ({ ...current, department: event.target.value }))} />

            <label className="flex items-center gap-3 rounded-2xl border border-softBorder px-4 py-3">
              <input
                type="checkbox"
                checked={form.is_active}
                onChange={(event) => setForm((current) => ({ ...current, is_active: event.target.checked }))}
              />
              <span className="text-sm font-semibold text-slate-700">Active employee</span>
            </label>

            <div className="flex flex-wrap gap-3">
              <Button type="submit" disabled={saving}>{saving ? 'Saving...' : form.id ? 'Update employee' : 'Create employee'}</Button>
              <Button type="button" variant="ghost" onClick={() => setForm(emptyForm)}>Clear</Button>
            </div>
          </form>
        </Card>

        <Card title="Employees" subtitle="Search by employee ID, name, email, or department.">
          <Input label="Search" placeholder="Search employees..." value={search} onChange={(event) => setSearch(event.target.value)} />

          <div className="mt-4 space-y-3">
            {loading ? <div className="rounded-2xl border border-softBorder p-4 text-sm text-slate-500">Loading employees...</div> : null}

            {!loading && filteredEmployees.map((employee) => (
              <div key={employee.id} className="rounded-2xl border border-softBorder p-4">
                <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-semibold text-slate-900">{employee.full_name}</p>
                      <Badge tone={employee.is_active ? 'active' : 'inactive'}>
                        {employee.is_active ? 'active' : 'inactive'}
                      </Badge>
                    </div>
                    <p className="mt-1 text-sm text-slate-600">{employee.employee_id} • {employee.email}</p>
                    <p className="mt-1 text-sm text-slate-500">{employee.department || 'No department'}</p>
                  </div>

                  <div className="flex gap-2">
                    <Button
                      type="button"
                      variant="ghost"
                      onClick={() => setForm({
                        id: employee.id,
                        employee_id: employee.employee_id,
                        full_name: employee.full_name,
                        email: employee.email,
                        department: employee.department || '',
                        is_active: employee.is_active,
                      })}
                    >
                      Edit
                    </Button>
                    <Button type="button" variant="danger" onClick={() => handleDelete(employee.id)}>
                      Delete
                    </Button>
                  </div>
                </div>
              </div>
            ))}

            {!loading && !filteredEmployees.length ? (
              <div className="rounded-2xl border border-dashed border-softBorder p-4 text-sm text-slate-500">No employees found.</div>
            ) : null}
          </div>
        </Card>
      </div>
    </>
  )
}
