const statusClasses = {
  pending: 'bg-[#FFF3BF] text-[#7A5400] ring-1 ring-[#FFE066]',
  approved: 'bg-[#D7EAFE] text-[#004B8D] ring-1 ring-[#9FCAFF]',
  ordered: 'bg-[#ECE3FF] text-[#5C2D91] ring-1 ring-[#D0B7FF]',
  fulfilled: 'bg-[#DBFCE7] text-[#166534] ring-1 ring-[#9EE6B8]',
  rejected: 'bg-[#FEE2E2] text-[#B91C1C] ring-1 ring-[#FECACA]',
  cancelled: 'bg-slate-200 text-slate-700 ring-1 ring-slate-300',
  in_stock: 'bg-[#DBFCE7] text-[#166534] ring-1 ring-[#9EE6B8]',
  size_up: 'bg-[#FFF3BF] text-[#7A5400] ring-1 ring-[#FFE066]',
  special_request: 'bg-[#FEE9D7] text-[#B45309] ring-1 ring-[#FDBA74]',
  low: 'bg-[#FEE2E2] text-[#B91C1C] ring-1 ring-[#FECACA]',
  healthy: 'bg-slate-100 text-slate-700 ring-1 ring-slate-200',
}

export default function Badge({ children, tone }) {
  return <span className={`badge ${statusClasses[tone] ?? 'bg-slate-100 text-slate-700 ring-1 ring-slate-200'}`}>{children}</span>
}
