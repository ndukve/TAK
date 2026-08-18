import type * as React from "react"

import { cn } from "@/lib/utils"
import { Icon } from "@/components/ui/icon"

/** In-progress indicator — spinning Remix loader glyph. */
export function Spinner({
  className,
  ...props
}: Omit<React.ComponentProps<"i">, "children">) {
  return (
    <Icon
      data-slot="spinner"
      name="loader-4-line"
      className={cn("animate-spin text-muted-foreground", className)}
      {...props}
    />
  )
}
