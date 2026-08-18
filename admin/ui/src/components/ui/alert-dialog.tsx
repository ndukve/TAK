import type * as React from "react"
import { AlertDialog as AlertDialogPrimitive } from "@base-ui/react/alert-dialog"

import { cn } from "@/lib/utils"
import { CardBrackets } from "@/components/ui/card"

/**
 * Scout AlertDialog — gate for irreversible flows (decommission, deny,
 * destroy). Name the action bluntly in the title, state the consequence
 * in the description, and pair a plain cancel with a destructive
 * confirm. No dismiss X; the operator must choose. `tone="warning"` or
 * `tone="critical"` on the content draws the matching semantic border.
 */
export function AlertDialog(props: AlertDialogPrimitive.Root.Props) {
  return <AlertDialogPrimitive.Root {...props} />
}

export function AlertDialogTrigger(props: AlertDialogPrimitive.Trigger.Props) {
  return (
    <AlertDialogPrimitive.Trigger data-slot="alert-dialog-trigger" {...props} />
  )
}

export function AlertDialogContent({
  className,
  tone = "neutral",
  children,
  ...props
}: AlertDialogPrimitive.Popup.Props & {
  /** Draws the matching operational border around the panel. */
  tone?: "neutral" | "warning" | "critical"
}) {
  return (
    <AlertDialogPrimitive.Portal>
      <AlertDialogPrimitive.Backdrop
        data-slot="alert-dialog-backdrop"
        className={cn(
          "fixed inset-0 z-50 bg-overlay transition-opacity duration-180 ease-standard",
          "data-ending-style:opacity-0 data-starting-style:opacity-0"
        )}
      />
      <AlertDialogPrimitive.Popup
        data-slot="alert-dialog-content"
        data-tone={tone}
        className={cn(
          "fixed top-1/2 left-1/2 z-50 w-full max-w-md -translate-x-1/2 -translate-y-1/2 border border-border bg-surface-raised p-5 text-foreground shadow-xl transition-[opacity,translate] duration-180 ease-standard outline-none light:[&>[data-slot=card-brackets]]:hidden",
          "data-starting-style:translate-y-[calc(-50%+8px)] data-starting-style:opacity-0",
          "data-ending-style:translate-y-[calc(-50%+8px)] data-ending-style:opacity-0",
          tone === "warning" &&
            "border-warning-border [--bracket-color:var(--warning)]",
          tone === "critical" &&
            "border-critical-border [--bracket-color:var(--critical)]",
          className
        )}
        {...props}
      >
        <CardBrackets />
        {children}
      </AlertDialogPrimitive.Popup>
    </AlertDialogPrimitive.Portal>
  )
}

export function AlertDialogTitle({
  className,
  ...props
}: AlertDialogPrimitive.Title.Props) {
  return (
    <AlertDialogPrimitive.Title
      data-slot="alert-dialog-title"
      className={cn("font-display text-lg", className)}
      {...props}
    />
  )
}

export function AlertDialogDescription({
  className,
  ...props
}: AlertDialogPrimitive.Description.Props) {
  return (
    <AlertDialogPrimitive.Description
      data-slot="alert-dialog-description"
      className={cn("mt-1 text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

export function AlertDialogFooter({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="alert-dialog-footer"
      className={cn("mt-5 flex justify-end gap-2", className)}
      {...props}
    />
  )
}

export function AlertDialogClose(props: AlertDialogPrimitive.Close.Props) {
  return (
    <AlertDialogPrimitive.Close data-slot="alert-dialog-close" {...props} />
  )
}
