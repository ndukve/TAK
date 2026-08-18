import type * as React from "react"

import { cn } from "@/lib/utils"

type Tone = "primary" | "nominal" | "warning" | "critical" | "signal"

const toneClasses: Record<Tone, string> = {
  primary: "bg-primary",
  nominal: "bg-nominal",
  warning: "bg-warning",
  critical: "bg-critical",
  signal: "bg-signal",
}

/**
 * Progress — linear meter. Continuous bar by default; pass `segments` for
 * the segmented instrument-panel gauge. `showValue` prints a mono readout.
 */
export function Progress({
  className,
  value,
  max = 100,
  tone = "primary",
  segments,
  showValue = false,
  label,
  ...props
}: Omit<React.ComponentProps<"div">, "children"> & {
  value: number
  max?: number
  tone?: Tone
  /** Number of discrete blocks; filled proportionally. */
  segments?: number
  showValue?: boolean
  label?: React.ReactNode
}) {
  const ratio = max > 0 ? Math.min(Math.max(value / max, 0), 1) : 0
  return (
    <div
      data-slot="progress"
      className={cn("flex min-w-0 flex-col gap-1.5", className)}
      {...props}
    >
      {(label != null || showValue) && (
        <div className="flex items-baseline justify-between gap-2">
          {label != null ? (
            <span className="scout-label">{label}</span>
          ) : (
            <span />
          )}
          {showValue && (
            <span className="font-mono text-xs text-muted-foreground tabular-nums">
              {Math.round(ratio * 100)}%
            </span>
          )}
        </div>
      )}
      {segments != null && segments > 0 ? (
        <div
          role="progressbar"
          aria-valuenow={value}
          aria-valuemin={0}
          aria-valuemax={max}
          className="flex h-2.5 items-stretch gap-px"
        >
          {Array.from({ length: segments }, (_, i) => (
            <span
              key={i}
              className={cn(
                "min-w-0 flex-1 transition-colors duration-180 ease-standard",
                i < Math.round(ratio * segments)
                  ? toneClasses[tone]
                  : "bg-neutral-surface"
              )}
            />
          ))}
        </div>
      ) : (
        <div
          role="progressbar"
          aria-valuenow={value}
          aria-valuemin={0}
          aria-valuemax={max}
          className="h-1.5 w-full overflow-hidden bg-neutral-surface"
        >
          <div
            className={cn(
              "h-full transition-[width] duration-280 ease-standard",
              toneClasses[tone]
            )}
            style={{ width: `${ratio * 100}%` }}
          />
        </div>
      )}
    </div>
  )
}
