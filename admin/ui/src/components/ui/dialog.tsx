import type * as React from "react"
import { Dialog as DialogPrimitive } from "@base-ui/react/dialog"

import { cn } from "@/lib/utils"
import { CardBrackets } from "@/components/ui/card"
import { Icon } from "@/components/ui/icon"

/**
 * Scout Dialog — modal bracketed panel over the scrim. Compose
 * `<Dialog>` → `<DialogTrigger>` + `<DialogContent>` with
 * `<DialogHeader>` / `<DialogDescription>` / `<DialogFooter>` inside.
 * For irreversible flows use AlertDialog instead.
 */
export function Dialog(props: DialogPrimitive.Root.Props) {
  return <DialogPrimitive.Root {...props} />
}

export function DialogTrigger(props: DialogPrimitive.Trigger.Props) {
  return <DialogPrimitive.Trigger data-slot="dialog-trigger" {...props} />
}

export function DialogContent({
  className,
  showClose = true,
  children,
  ...props
}: DialogPrimitive.Popup.Props & {
  /** Render the top-right close control (default true). */
  showClose?: boolean
}) {
  return (
    <DialogPrimitive.Portal>
      <DialogPrimitive.Backdrop
        data-slot="dialog-backdrop"
        className={cn(
          "fixed inset-0 z-50 bg-overlay transition-opacity duration-180 ease-standard",
          "data-ending-style:opacity-0 data-starting-style:opacity-0"
        )}
      />
      <DialogPrimitive.Popup
        data-slot="dialog-content"
        className={cn(
          "fixed top-1/2 left-1/2 z-50 w-full max-w-md -translate-x-1/2 -translate-y-1/2 border border-border bg-surface-raised p-5 text-foreground shadow-xl transition-[opacity,translate] duration-180 ease-standard outline-none light:[&>[data-slot=card-brackets]]:hidden",
          "data-starting-style:translate-y-[calc(-50%+8px)] data-starting-style:opacity-0",
          "data-ending-style:translate-y-[calc(-50%+8px)] data-ending-style:opacity-0",
          className
        )}
        {...props}
      >
        <CardBrackets />
        {showClose && (
          <DialogPrimitive.Close
            data-slot="dialog-close-x"
            aria-label="Close"
            className="absolute top-3 right-3 flex size-7 items-center justify-center text-muted-foreground transition-colors duration-120 ease-standard outline-none hover:bg-neutral-surface hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring"
          >
            <Icon name="close-line" className="text-[1rem]" />
          </DialogPrimitive.Close>
        )}
        {children}
      </DialogPrimitive.Popup>
    </DialogPrimitive.Portal>
  )
}

export function DialogHeader({
  className,
  label,
  title,
  children,
  ...props
}: React.ComponentProps<"div"> & {
  /** Mono uppercase eyebrow above the title. */
  label?: React.ReactNode
  title?: React.ReactNode
}) {
  return (
    <div
      data-slot="dialog-header"
      className={cn("mb-4 flex min-w-0 flex-col gap-1", className)}
      {...props}
    >
      {label != null && (
        <span className="scout-label [overflow-wrap:anywhere]">{label}</span>
      )}
      {title != null && <DialogTitle>{title}</DialogTitle>}
      {children}
    </div>
  )
}

export function DialogTitle({
  className,
  ...props
}: DialogPrimitive.Title.Props) {
  return (
    <DialogPrimitive.Title
      data-slot="dialog-title"
      className={cn("font-display text-lg [overflow-wrap:anywhere]", className)}
      {...props}
    />
  )
}

export function DialogDescription({
  className,
  ...props
}: DialogPrimitive.Description.Props) {
  return (
    <DialogPrimitive.Description
      data-slot="dialog-description"
      className={cn("text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

export function DialogFooter({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="dialog-footer"
      className={cn("mt-5 flex justify-end gap-2", className)}
      {...props}
    />
  )
}

export function DialogClose(props: DialogPrimitive.Close.Props) {
  return <DialogPrimitive.Close data-slot="dialog-close" {...props} />
}
