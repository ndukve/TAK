import type * as React from "react"

import { cn } from "@/lib/utils"

type Tone = "default" | "primary" | "nominal" | "warning" | "critical"

const toneClasses: Record<Tone, string> = {
  default: "text-foreground",
  primary: "text-primary-emphasis",
  nominal: "text-nominal",
  warning: "text-warning",
  critical: "text-critical",
}

/* Unit/trend readouts scale with the numeral so they stay legible beside it. */
const valueSizes = {
  sm: "text-2xl",
  default: "text-4xl",
  lg: "text-5xl",
} as const

const metaSizes = {
  sm: "text-xs",
  default: "text-md",
  lg: "text-lg",
} as const

/**
 * Scout Stat — big Oxanium numeric readout with mono label. The signature
 * telemetry element ("SYSTEM VITALS"). Use for dashboards, vitals panels,
 * and metric grids.
 */
export function Stat({
  className,
  label,
  value,
  unit,
  tone = "default",
  hint,
  size = "default",
  trend,
  ...props
}: React.ComponentProps<"div"> & {
  label?: React.ReactNode
  value: React.ReactNode
  unit?: React.ReactNode
  tone?: Tone
  hint?: React.ReactNode
  size?: "sm" | "default" | "lg"
  trend?: React.ReactNode
}) {
  return (
    <div
      data-slot="stat"
      className={cn("flex min-w-0 flex-col gap-1", className)}
      {...props}
    >
      {label != null && <span className="scout-label">{label}</span>}
      <div className="flex items-baseline gap-2">
        <span
          className={cn(
            "font-display leading-none tracking-tight tabular-nums",
            valueSizes[size],
            toneClasses[tone]
          )}
        >
          {value}
        </span>
        {unit != null && (
          <span
            className={cn(
              "font-mono font-medium text-subtle tabular-nums",
              metaSizes[size]
            )}
          >
            {unit}
          </span>
        )}
        {trend != null && (
          <span
            className={cn(
              "font-mono font-medium tabular-nums",
              metaSizes[size],
              toneClasses[tone]
            )}
          >
            {trend}
          </span>
        )}
      </div>
      {hint != null && <span className="text-xs text-subtle">{hint}</span>}
    </div>
  )
}
