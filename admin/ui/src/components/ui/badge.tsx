import type * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

const badgeVariants = cva(
  "inline-flex h-5 shrink-0 items-center gap-1 border px-1.5 font-mono text-2xs tracking-wide whitespace-nowrap uppercase [&_i[class^='ri-']]:text-[0.8rem]",
  {
    variants: {
      variant: {
        neutral: "border-border bg-neutral-surface text-muted-foreground",
        primary: "border-transparent bg-primary-soft text-primary-emphasis",
        outline: "border-border-strong text-foreground",
        nominal: "border-nominal-border bg-nominal-surface text-nominal",
        warning: "border-warning-border bg-warning-surface text-warning",
        critical: "border-critical-border bg-critical-surface text-critical",
      },
    },
    defaultVariants: {
      variant: "neutral",
    },
  }
)

/**
 * Scout Badge — small mono tag for counts, versions, flags ("V3", "TLS",
 * "12 NODES"). For operational state use Status instead. `plain` drops the
 * border, fill, and box height for inline use beside labels and buttons.
 */
export function Badge({
  className,
  variant,
  plain = false,
  ...props
}: React.ComponentProps<"span"> &
  VariantProps<typeof badgeVariants> & { plain?: boolean }) {
  return (
    <span
      data-slot="badge"
      className={cn(
        badgeVariants({ variant }),
        plain && "h-auto border-0 bg-transparent px-0",
        className
      )}
      {...props}
    />
  )
}

export { badgeVariants }
