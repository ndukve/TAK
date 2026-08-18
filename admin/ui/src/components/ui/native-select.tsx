import type * as React from "react"

import { cn } from "@/lib/utils"
import { Icon } from "@/components/ui/icon"

type Option = string | { value: string; label: React.ReactNode }

/**
 * NativeSelect — the browser-native select with Scout styling. Prefer the
 * styled `Select` (Base UI dropdown) for app UI; reach for this only where
 * the OS picker is genuinely better (tiny inline editors, mobile-heavy
 * forms, extreme option counts).
 */
export function NativeSelect({
  className,
  label,
  hint,
  options,
  invalid = false,
  children,
  ...props
}: React.ComponentProps<"select"> & {
  label?: React.ReactNode
  hint?: React.ReactNode
  options?: Option[]
  invalid?: boolean
}) {
  const control = (
    <span className="relative block w-full">
      <select
        data-slot="native-select"
        aria-invalid={invalid || undefined}
        className={cn(
          "h-9 w-full min-w-0 cursor-pointer appearance-none border bg-surface-inset pr-8 pl-3 font-sans text-sm text-foreground transition-[border-color,box-shadow] duration-120 ease-standard outline-none",
          "focus-visible:border-primary focus-visible:ring-3 focus-visible:ring-ring",
          "disabled:cursor-not-allowed disabled:opacity-50",
          "aria-invalid:border-critical-border",
          className
        )}
        {...props}
      >
        {children ??
          options?.map((o) => {
            const value = typeof o === "string" ? o : o.value
            const text = typeof o === "string" ? o : o.label
            return (
              <option key={value} value={value}>
                {text}
              </option>
            )
          })}
      </select>
      <Icon
        name="arrow-down-s-line"
        className="pointer-events-none absolute top-1/2 right-2 -translate-y-1/2 text-[1rem] text-muted-foreground"
      />
    </span>
  )
  if (label == null && hint == null) return control
  return (
    <label className="flex flex-col gap-1.5">
      {label != null && <span className="scout-label">{label}</span>}
      {control}
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
