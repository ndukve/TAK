import type * as React from "react"

import { cn } from "@/lib/utils"

/**
 * Scout Textarea — multi-line field on the inset surface. Optional mono
 * uppercase `label` and `hint` wrap the field; `mono` is for data entry
 * (configs, key expressions); `invalid` draws the critical border.
 */
export function Textarea({
  className,
  label,
  hint,
  invalid = false,
  mono = false,
  ...props
}: React.ComponentProps<"textarea"> & {
  label?: React.ReactNode
  hint?: React.ReactNode
  invalid?: boolean
  /** Monospace field for identifiers, key expressions, config fragments. */
  mono?: boolean
}) {
  const field = (
    <textarea
      data-slot="textarea"
      aria-invalid={invalid || undefined}
      className={cn(
        "min-h-20 w-full min-w-0 resize-y border bg-surface-inset px-3 py-2 font-sans text-sm text-foreground transition-[border-color,box-shadow] duration-120 ease-standard outline-none",
        "placeholder:text-subtle",
        "focus-visible:border-primary focus-visible:ring-3 focus-visible:ring-ring",
        "disabled:cursor-not-allowed disabled:opacity-50",
        "aria-invalid:border-critical-border",
        mono && "font-mono text-xs",
        className
      )}
      {...props}
    />
  )
  if (label == null && hint == null) return field
  return (
    <label className="flex flex-col gap-1.5">
      {label != null && <span className="scout-label">{label}</span>}
      {field}
      {hint != null && (
        <span
          className={cn("text-xs", invalid ? "text-critical" : "text-subtle")}
        >
          {hint}
        </span>
      )}
    </label>
  )
}
