export default function PageHeader({ eyebrow, title, description, actions }) {
  return (
    <div className="flex flex-col gap-4 rounded-[28px] bg-gradient-to-r from-[#0058A3] to-[#0A7BD8] p-6 text-white shadow-soft lg:flex-row lg:items-end lg:justify-between">
      <div>
        {eyebrow ? <div className="text-xs font-bold uppercase tracking-[0.25em] text-[#FFDA1A]">{eyebrow}</div> : null}
        <h1 className="mt-2 text-2xl font-bold sm:text-3xl">{title}</h1>
        {description ? <p className="mt-3 max-w-3xl text-sm text-blue-100 sm:text-base">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap gap-3">{actions}</div> : null}
    </div>
  )
}
