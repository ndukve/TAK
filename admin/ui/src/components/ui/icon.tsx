import type * as React from "react"

import { cn } from "@/lib/utils"

/**
 * Scout Icon — Remix Icon glyph. Pass `name` WITHOUT the "ri-" prefix,
 * e.g. `<Icon name="router-line" />`. Prefer `-line` glyphs for UI chrome,
 * `-fill` for emphasis/status. Inherits `currentColor`; size with the
 * `size` prop or a text-size/`text-[…]` class.
 */
export function Icon({
  name,
  size,
  className,
  style,
  ...props
}: Omit<React.ComponentProps<"i">, "children"> & {
  name: string
  size?: string | number
}) {
  return (
    <i
      data-slot="icon"
      aria-hidden="true"
      className={cn(`ri-${name}`, "inline-flex leading-none", className)}
      style={size != null ? { fontSize: size, ...style } : style}
      {...props}
    />
  )
}
