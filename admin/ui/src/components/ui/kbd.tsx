import type * as React from "react"

import { cn } from "@/lib/utils"

/** Keyboard key cap — mono, square, inset. */
export function Kbd({ className, ...props }: React.ComponentProps<"kbd">) {
  return (
    <kbd
      data-slot="kbd"
      className={cn(
        "inline-flex h-5 min-w-5 items-center justify-center border border-border bg-surface-inset px-1 font-mono text-2xs font-medium text-muted-foreground",
        className
      )}
      {...props}
    />
  )
}
