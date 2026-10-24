interface PageHeaderProps {
  title: string
  /** Kept for the existing call sites; the muted section marker above the title is gone. */
  eyebrow?: string
  count?: number
  countLabel?: string
  actions?: React.ReactNode
}

export function PageHeader({ title, count, countLabel, actions }: PageHeaderProps) {
  return (
    <div className="flex items-end justify-between mb-6 pb-4">
      <div className="flex items-baseline gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        {count !== undefined && (
          <span className="text-xs text-zinc-500">{count} {countLabel}</span>
        )}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  )
}
