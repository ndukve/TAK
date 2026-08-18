import type * as React from "react"

import { cn } from "@/lib/utils"

/**
 * Corner-bracket frame — the hardened "instrument panel" motif. Rendered by
 * Card by default; reuse on any positioned container that needs the treatment.
 */
export function CardBrackets({ className }: { className?: string }) {
  const corner =
    "pointer-events-none absolute size-[10px] border-(--bracket-color)"
  return (
    <span
      aria-hidden="true"
      className={cn("pointer-events-none absolute inset-0", className)}
      data-slot="card-brackets"
    >
      <span className={cn(corner, "-top-px -left-px border-t border-l")} />
      <span className={cn(corner, "-top-px -right-px border-t border-r")} />
      <span className={cn(corner, "-bottom-px -left-px border-b border-l")} />
      <span className={cn(corner, "-right-px -bottom-px border-r border-b")} />
    </span>
  )
}

export function Card({
  className,
  bracketed = true,
  inset = false,
  children,
  ...props
}: React.ComponentProps<"div"> & {
  /** Corner-bracket frame (default true) — the universal Scout panel treatment. */
  bracketed?: boolean
  /** Sunken surface for wells and nested panels. */
  inset?: boolean
}) {
  return (
    <div
      data-slot="card"
      data-bracketed={bracketed || undefined}
      className={cn(
        "relative border bg-surface p-5 text-foreground shadow-sm",
        inset && "bg-surface-inset shadow-none",
        className
      )}
      {...props}
    >
      {bracketed ? <CardBrackets /> : null}
      {children}
    </div>
  )
}

export function CardHeader({
  className,
  label,
  title,
  action,
  children,
  ...props
}: Omit<React.ComponentProps<"div">, "title"> & {
  /** Mono uppercase eyebrow above the title. */
  label?: React.ReactNode
  title?: React.ReactNode
  /** Right-aligned slot (Status pill, button, …). */
  action?: React.ReactNode
}) {
  return (
    <div
      data-slot="card-header"
      className={cn("mb-4 flex items-start justify-between gap-4", className)}
      {...props}
    >
      <div className="flex min-w-0 flex-col gap-1">
        {label != null && <span className="scout-label">{label}</span>}
        {title != null && <CardTitle>{title}</CardTitle>}
        {children}
      </div>
      {action != null && <div className="shrink-0">{action}</div>}
    </div>
  )
}

export function CardTitle({ className, ...props }: React.ComponentProps<"h3">) {
  return (
    <h3
      data-slot="card-title"
      className={cn("font-display text-lg", className)}
      {...props}
    />
  )
}

export function CardDescription({
  className,
  ...props
}: React.ComponentProps<"p">) {
  return (
    <p
      data-slot="card-description"
      className={cn("text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

export function CardContent({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return <div data-slot="card-content" className={cn(className)} {...props} />
}

export function CardFooter({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-footer"
      className={cn("mt-4 flex items-center gap-2", className)}
      {...props}
    />
  )
}
