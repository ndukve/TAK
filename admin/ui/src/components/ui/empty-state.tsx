import type * as React from "react"

import { cn } from "@/lib/utils"
import { Icon } from "@/components/ui/icon"

/**
 * EmptyState — honest empty/zero state. Say what is absent and why
 * ("No parent contact has been recorded."), never fake optimism.
 */
export function EmptyState({
  className,
  icon = "inbox-line",
  title,
  hint,
  action,
  bracketed = true,
  children,
  ...props
}: Omit<React.ComponentProps<"div">, "title"> & {
  /** Remix glyph name. */
  icon?: string
  title: React.ReactNode
  hint?: React.ReactNode
  action?: React.ReactNode
  /** Corner brackets — pass false when composed inside a bracketed panel. */
  bracketed?: boolean
}) {
  return (
    <div
      data-slot="empty-state"
      className={cn(
        "flex flex-col items-center gap-2 border border-border px-6 py-10 text-center",
        bracketed && "scout-bracketed",
        className
      )}
      {...props}
    >
      <span className="mb-1 inline-flex size-10 items-center justify-center border border-border bg-surface-inset">
        <Icon name={icon} className="text-[1.25rem] text-muted-foreground" />
      </span>
      <p className="font-display text-md text-foreground">{title}</p>
      {hint != null && (
        <p className="max-w-sm text-sm text-muted-foreground">{hint}</p>
      )}
      {children}
      {action != null && <div className="mt-3">{action}</div>}
    </div>
  )
}
