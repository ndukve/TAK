import type * as React from "react"

import { cn } from "@/lib/utils"

/**
 * Scout Label — the signature mono uppercase micro-label. Used as form
 * label, section eyebrow, and telemetry caption ("SYSTEM VITALS").
 */
export function Label({ className, ...props }: React.ComponentProps<"label">) {
  return (
    <label
      data-slot="label"
      className={cn(
        "scout-label inline-flex items-center gap-1.5 select-none",
        className
      )}
      {...props}
    />
  )
}
