import type * as React from "react"
import { Select as SelectPrimitive } from "@base-ui/react/select"

import { cn } from "@/lib/utils"
import { Icon } from "@/components/ui/icon"

/**
 * Scout Select — styled dropdown on Base UI (the default select; the
 * browser-native variant lives in native-select.tsx). Compose the parts
 * for custom layouts, or use the `Select` convenience wrapper with
 * `options` + mono `label` for the common form field.
 */

export function SelectRoot(props: SelectPrimitive.Root.Props<string>) {
  return <SelectPrimitive.Root data-slot="select" {...props} />
}

export function SelectTrigger({
  className,
  invalid = false,
  children,
  ...props
}: SelectPrimitive.Trigger.Props & { invalid?: boolean }) {
  return (
    <SelectPrimitive.Trigger
      data-slot="select-trigger"
      aria-invalid={invalid || undefined}
      className={cn(
        "flex h-9 w-full min-w-0 cursor-pointer items-center justify-between gap-2 border bg-surface-inset pr-2 pl-3 font-sans text-sm text-foreground transition-[border-color,box-shadow] duration-120 ease-standard outline-none select-none",
        "focus-visible:border-primary focus-visible:ring-3 focus-visible:ring-ring",
        "data-popup-open:border-primary",
        "data-disabled:cursor-not-allowed data-disabled:opacity-50",
        "aria-invalid:border-critical-border",
        className
      )}
      {...props}
    >
      {children}
      {/* Explicit children replace Base UI's default "▼" glyph. */}
      <SelectPrimitive.Icon className="flex shrink-0">
        <Icon
          name="arrow-down-s-line"
          className="text-[1rem] text-muted-foreground"
        />
      </SelectPrimitive.Icon>
    </SelectPrimitive.Trigger>
  )
}

export function SelectValue({
  className,
  ...props
}: SelectPrimitive.Value.Props) {
  return (
    <SelectPrimitive.Value
      data-slot="select-value"
      className={cn("truncate data-[placeholder]:text-subtle", className)}
      {...props}
    />
  )
}

export function SelectContent({
  className,
  sideOffset = 4,
  children,
  ...props
}: SelectPrimitive.Popup.Props & {
  sideOffset?: number
}) {
  return (
    <SelectPrimitive.Portal>
      <SelectPrimitive.Positioner
        className="z-50 outline-none"
        sideOffset={sideOffset}
        alignItemWithTrigger={false}
      >
        <SelectPrimitive.Popup
          data-slot="select-content"
          className={cn(
            "max-h-[min(24rem,var(--available-height))] min-w-(--anchor-width) overflow-y-auto border border-border bg-surface-raised p-1 text-foreground shadow-lg outline-none",
            "transition-opacity duration-120 ease-standard data-ending-style:opacity-0 data-starting-style:opacity-0",
            className
          )}
          {...props}
        >
          {children}
        </SelectPrimitive.Popup>
      </SelectPrimitive.Positioner>
    </SelectPrimitive.Portal>
  )
}

export function SelectItem({
  className,
  children,
  ...props
}: SelectPrimitive.Item.Props) {
  return (
    <SelectPrimitive.Item
      data-slot="select-item"
      className={cn(
        "relative flex h-8 cursor-default items-center gap-2 pr-8 pl-2.5 text-sm text-foreground outline-none select-none",
        "data-highlighted:bg-neutral-surface",
        "data-disabled:pointer-events-none data-disabled:opacity-45",
        className
      )}
      {...props}
    >
      <SelectPrimitive.ItemText className="truncate">
        {children}
      </SelectPrimitive.ItemText>
      {/* Explicit children replace Base UI's default "✔" glyph. */}
      <SelectPrimitive.ItemIndicator className="absolute right-2.5 flex">
        <Icon
          name="check-line"
          className="text-[0.9rem] text-primary-emphasis"
        />
      </SelectPrimitive.ItemIndicator>
    </SelectPrimitive.Item>
  )
}

export function SelectGroup(props: SelectPrimitive.Group.Props) {
  return <SelectPrimitive.Group data-slot="select-group" {...props} />
}

export function SelectGroupLabel({
  className,
  ...props
}: SelectPrimitive.GroupLabel.Props) {
  return (
    <SelectPrimitive.GroupLabel
      data-slot="select-group-label"
      className={cn("scout-label flex h-7 items-center px-2.5", className)}
      {...props}
    />
  )
}

export function SelectSeparator({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="select-separator"
      role="separator"
      className={cn("my-1 h-px bg-border", className)}
      {...props}
    />
  )
}

type Option = string | { value: string; label: React.ReactNode }

/**
 * Convenience form-field wrapper: mono `label`, `hint`, `invalid`, and an
 * `options` list. Controlled via `value` / `onValueChange`.
 */
export function Select({
  label,
  hint,
  invalid = false,
  options = [],
  placeholder = "Select…",
  className,
  "aria-label": ariaLabel,
  ...rootProps
}: Omit<SelectPrimitive.Root.Props<string>, "items"> & {
  label?: React.ReactNode
  hint?: React.ReactNode
  invalid?: boolean
  options?: Option[]
  placeholder?: React.ReactNode
  /** Applied to the trigger. */
  className?: string
  "aria-label"?: string
}) {
  const items = options.map((o) =>
    typeof o === "string" ? { value: o, label: o } : o
  )
  const control = (
    <SelectRoot items={items} {...rootProps}>
      <SelectTrigger
        invalid={invalid}
        className={className}
        aria-label={ariaLabel}
      >
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        {items.map((item) => (
          <SelectItem key={item.value} value={item.value}>
            {item.label}
          </SelectItem>
        ))}
      </SelectContent>
    </SelectRoot>
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
