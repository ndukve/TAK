import type * as React from "react"

import { cn } from "@/lib/utils"
import { CardBrackets } from "@/components/ui/card"
import { Icon } from "@/components/ui/icon"

type Tone = "neutral" | "nominal" | "warning" | "critical"

const toneClasses: Record<Tone, string> = {
  neutral: "border-border bg-neutral-surface/60 [&>i]:text-muted-foreground",
  nominal:
    "border-nominal-border bg-nominal-surface [--bracket-color:var(--nominal)] [&>i]:text-nominal",
  warning:
    "border-warning-border bg-warning-surface [--bracket-color:var(--warning)] [&>i]:text-warning",
  critical:
    "border-critical-border bg-critical-surface [--bracket-color:var(--critical)] [&>i]:text-critical",
}

const toneIcons: Record<Tone, string> = {
  neutral: "information-line",
  nominal: "checkbox-circle-line",
  warning: "error-warning-line",
  critical: "alert-line",
}

/**
 * Scout Alert — inline callout. State what happened and what remains safe.
 * Compose with AlertTitle + AlertDescription.
 */
export function Alert({
  className,
  tone = "neutral",
  icon,
  children,
  ...props
}: React.ComponentProps<"div"> & {
  tone?: Tone
  /** Remix glyph name overriding the tone default. */
  icon?: string
}) {
  return (
    <div
      data-slot="alert"
      data-bracketed=""
      role="alert"
      className={cn(
        "relative grid grid-cols-[auto_1fr] items-start gap-x-3 gap-y-0.5 border p-4 text-sm",
        toneClasses[tone],
        className
      )}
      {...props}
    >
      <CardBrackets />
      <Icon name={icon ?? toneIcons[tone]} className="mt-0.5 text-[1rem]" />
      <div className="flex min-w-0 flex-col gap-1">{children}</div>
    </div>
  )
}

export function AlertTitle({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="alert-title"
      className={cn("font-semibold text-foreground", className)}
      {...props}
    />
  )
}

export function AlertDescription({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="alert-description"
      className={cn("text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}
