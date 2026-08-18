import type * as React from "react"

import { cn } from "@/lib/utils"
import { Icon } from "@/components/ui/icon"

type Tone = "neutral" | "nominal" | "warning" | "critical"

const toneClasses: Record<Tone, string> = {
  neutral: "border-border bg-neutral-surface text-muted-foreground",
  nominal: "border-nominal-border bg-nominal-surface text-nominal",
  warning: "border-warning-border bg-warning-surface text-warning",
  critical: "border-critical-border bg-critical-surface text-critical",
}

const toneIcons: Record<Tone, string> = {
  neutral: "question-line",
  nominal: "checkbox-circle-line",
  warning: "error-warning-line",
  critical: "close-circle-line",
}

/**
 * Scout Status — operational status pill, the pervasive health signal.
 * Map connectivity/health/lifecycle states to a tone; keep the label short
 * ("Online", "Stale", "Local only"). `dot` for a minimal filled indicator,
 * `pulse` for a live telemetry dot.
 */
export function Status({
  children,
  className,
  tone = "neutral",
  icon,
  dot = false,
  pulse = false,
  plain = false,
  ...props
}: React.ComponentProps<"span"> & {
  tone?: Tone
  /** Remix glyph name overriding the tone default. */
  icon?: string
  /** Render a small filled square instead of a glyph. */
  dot?: boolean
  /** Render a pulsing live dot (telemetry). Implies `dot`. */
  pulse?: boolean
  /** No border, fill, or box height — inline beside labels and buttons. */
  plain?: boolean
}) {
  return (
    <span
      data-slot="status"
      className={cn(
        "inline-flex h-6 items-center gap-1.5 border px-2.5 font-mono text-2xs tracking-wide whitespace-nowrap uppercase",
        toneClasses[tone],
        plain && "h-auto border-0 bg-transparent px-0",
        className
      )}
      {...props}
    >
      {dot || pulse ? (
        <span
          className={cn(
            "size-1.5 bg-current",
            pulse && "animate-scout-pulse shadow-[var(--glow-signal)]"
          )}
        />
      ) : (
        <Icon name={icon ?? toneIcons[tone]} className="text-[0.875rem]" />
      )}
      {children}
    </span>
  )
}
