export default function SimpleBarChart({ items = [], emptyLabel = 'No data yet' }) {
  if (!items.length) {
    return <div className="rounded-2xl bg-slate-50 p-4 text-sm text-slate-500">{emptyLabel}</div>
  }

  const maxValue = Math.max(...items.map((item) => item.value), 1)

  return (
    <div className="space-y-4">
      {items.map((item) => (
        <div key={item.label}>
          <div className="mb-2 flex items-center justify-between gap-3 text-sm">
            <span className="font-medium text-ink">{item.label}</span>
            <span className="text-slate-500">{item.value}</span>
          </div>
          <div className="h-3 rounded-full bg-slate-100">
            <div
              className="h-3 rounded-full bg-gradient-to-r from-ikeaBlue to-[#0A7BD8]"
              style={{ width: `${Math.max((item.value / maxValue) * 100, item.value > 0 ? 8 : 0)}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  )
}
