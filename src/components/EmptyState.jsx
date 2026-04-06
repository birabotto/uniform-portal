export default function EmptyState({ title, description, action }) {
  return (
    <div className="card p-8 text-center">
      <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-slate-100 text-2xl">📦</div>
      <div className="mt-4 text-lg font-semibold text-ink">{title}</div>
      <div className="mt-2 text-sm text-slate-500">{description}</div>
      {action ? <div className="mt-5">{action}</div> : null}
    </div>
  )
}
