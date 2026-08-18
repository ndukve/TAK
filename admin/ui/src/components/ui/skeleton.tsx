import type * as React from "react"

import { cn } from "@/lib/utils"

/** Loading placeholder — square, quiet pulse. */
export function Skeleton({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="skeleton"
      className={cn("animate-pulse bg-neutral-surface", className)}
      {...props}
    />
  )
}
