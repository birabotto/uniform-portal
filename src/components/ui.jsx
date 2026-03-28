export function PageHeader({ title, description, action, eyebrow = '' }) {
  return (
    <div className="flex flex-col gap-4 rounded-[28px] border border-softBorder bg-white p-6 shadow-soft md:flex-row md:items-end md:justify-between">
      <div>
        {eyebrow ? <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-ikeaBlue">{eyebrow}</p> : null}
        <h1 className="mt-2 text-[2rem] font-extrabold text-slate-900">{title}</h1>
        {description ? <p className="mt-2 text-sm text-slate-600">{description}</p> : null}
      </div>
      {action ? <div>{action}</div> : null}
    </div>
  )
}

export function StatCard({ label, value, helper, tone = 'default' }) {
  const tones = {
    default: 'bg-white text-slate-900',
    yellow: 'bg-ikeaYellow text-slate-900',
    blue: 'bg-[#2f6ac0] text-white',
  }

  return (
    <div className={`rounded-[28px] border border-softBorder p-5 shadow-soft ${tones[tone] || tones.default}`}>
      <p className={`text-sm font-medium ${tone === 'blue' ? 'text-blue-100' : 'text-slate-500'}`}>{label}</p>
      <p className="mt-3 text-3xl font-extrabold">{value}</p>
      {helper ? <p className={`mt-3 text-sm leading-6 ${tone === 'blue' ? 'text-blue-50' : 'text-slate-500'}`}>{helper}</p> : null}
    </div>
  )
}

export function Card({ title, subtitle, children, action, className = '' }) {
  return (
    <section className={`rounded-[28px] border border-softBorder bg-white p-6 shadow-soft ${className}`}>
      {(title || subtitle || action) ? (
        <div className="mb-4 flex items-start justify-between gap-4">
          <div>
            {title ? <h2 className="text-[1.15rem] font-extrabold text-slate-900">{title}</h2> : null}
            {subtitle ? <p className="mt-1 text-sm text-slate-500">{subtitle}</p> : null}
          </div>
          {action}
        </div>
      ) : null}
      {children}
    </section>
  )
}

export function Badge({ children, tone = 'default' }) {
  const styles = {
    default: 'bg-slate-100 text-slate-700',
    pending: 'bg-[#fff3c4] text-[#7a5d00]',
    approved: 'bg-blue-100 text-blue-700',
    ordered: 'bg-indigo-100 text-indigo-700',
    completed: 'bg-emerald-100 text-emerald-700',
    cancelled: 'bg-rose-100 text-rose-700',
    special_request: 'bg-violet-100 text-violet-700',
    active: 'bg-emerald-100 text-emerald-700',
    inactive: 'bg-slate-100 text-slate-700',
  }

  return (
    <span className={`inline-flex rounded-full px-3 py-1 text-xs font-semibold ${styles[tone] || styles.default}`}>
      {children}
    </span>
  )
}

export function Input({ label, error, ...props }) {
  return (
    <label className="block">
      {label ? <span className="mb-2 block text-sm font-bold text-slate-900">{label}</span> : null}
      <input
        {...props}
        className={`w-full rounded-[18px] border px-4 py-3 text-sm outline-none transition ${
          props.readOnly
            ? 'border-[#d7e0ea] bg-[#f9fbfd] text-slate-700'
            : error
              ? 'border-red-300 bg-red-50'
              : 'border-[#b7c7da] bg-white focus:border-ikeaBlue focus:ring-2 focus:ring-blue-100'
        } ${props.className || ''}`}
      />
      {error ? <span className="mt-2 block text-xs text-red-600">{error}</span> : null}
    </label>
  )
}

export function Select({ label, children, ...props }) {
  return (
    <label className="block">
      {label ? <span className="mb-2 block text-sm font-bold text-slate-900">{label}</span> : null}
      <select
        {...props}
        className={`w-full rounded-[18px] border border-[#b7c7da] bg-white px-4 py-3 text-sm outline-none transition focus:border-ikeaBlue focus:ring-2 focus:ring-blue-100 disabled:bg-[#f8fafc] ${props.className || ''}`}
      >
        {children}
      </select>
    </label>
  )
}

export function Textarea({ label, ...props }) {
  return (
    <label className="block">
      {label ? <span className="mb-2 block text-sm font-bold text-slate-900">{label}</span> : null}
      <textarea
        {...props}
        className={`min-h-[120px] w-full rounded-[18px] border border-[#b7c7da] bg-white px-4 py-3 text-sm outline-none transition focus:border-ikeaBlue focus:ring-2 focus:ring-blue-100 ${props.className || ''}`}
      />
    </label>
  )
}

export function Button({ children, variant = 'primary', ...props }) {
  const styles = {
    primary: 'bg-ikeaBlue text-white hover:bg-ikeaNavy',
    secondary: 'bg-ikeaYellow text-slate-900 hover:brightness-95',
    ghost: 'bg-slate-100 text-slate-700 hover:bg-slate-200',
    danger: 'bg-rose-600 text-white hover:bg-rose-700',
  }

  return (
    <button
      {...props}
      className={`rounded-[18px] px-4 py-3 text-sm font-bold transition disabled:cursor-not-allowed disabled:opacity-50 ${styles[variant]} ${props.className || ''}`}
    >
      {children}
    </button>
  )
}
