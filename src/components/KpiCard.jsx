export default function KpiCard({ label, value, helper, accent = 'blue', trend }) {
  const accents = {
    blue: 'from-[#0058A3] to-[#0A7BD8] text-white',
    yellow: 'from-[#FFDA1A] to-[#FFE97B] text-slate-900',
    white: 'from-white to-slate-50 text-slate-900',
  }

  return (
    <div className={`rounded-[28px] border border-slate-200 bg-gradient-to-br p-5 shadow-soft ${accents[accent] ?? accents.white}`}>
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-sm font-medium opacity-80">{label}</div>
          <div className="mt-3 text-4xl font-bold tracking-tight">{value}</div>
        </div>
        {trend ? <div className="rounded-full bg-white/20 px-3 py-1 text-xs font-semibold">{trend}</div> : null}
      </div>
      <div className="mt-4 text-sm opacity-80">{helper}</div>
    </div>
  )
}
