import type * as React from "react"
import { Dialog as SheetPrimitive } from "@base-ui/react/dialog"

import { cn } from "@/lib/utils"
import { CardBrackets } from "@/components/ui/card"
import { Icon } from "@/components/ui/icon"

/**
 * Scout Sheet — edge-anchored side panel for inspect/edit tasks that keep
 * the page in view. Compose `<Sheet>` → `<SheetTrigger>` +
 * `<SheetContent side="right|left|top|bottom">` with `<SheetHeader>` /
 * `<SheetDescription>` / `<SheetFooter>` inside. Slides in mechanically
 * from its edge; for centered bounded tasks use Dialog instead.
 */
export function Sheet(props: SheetPrimitive.Root.Props) {
  return <SheetPrimitive.Root {...props} />
}

export function SheetTrigger(props: SheetPrimitive.Trigger.Props) {
  return <SheetPrimitive.Trigger data-slot="sheet-trigger" {...props} />
}

type SheetSide = "top" | "right" | "bottom" | "left"

const sideClasses: Record<SheetSide, string> = {
  right: cn(
    "inset-y-0 right-0 h-full w-3/4 border-l sm:max-w-sm",
    "data-ending-style:translate-x-full data-starting-style:translate-x-full"
  ),
  left: cn(
    "inset-y-0 left-0 h-full w-3/4 border-r sm:max-w-sm",
    "data-ending-style:-translate-x-full data-starting-style:-translate-x-full"
  ),
  top: cn(
    "inset-x-0 top-0 max-h-[80dvh] border-b",
    "data-ending-style:-translate-y-full data-starting-style:-translate-y-full"
  ),
  bottom: cn(
    "inset-x-0 bottom-0 max-h-[80dvh] border-t",
    "data-ending-style:translate-y-full data-starting-style:translate-y-full"
  ),
}

export function SheetContent({
  className,
  side = "right",
  showClose = true,
  children,
  ...props
}: SheetPrimitive.Popup.Props & {
  /** Edge the panel is anchored to (default right). */
  side?: SheetSide
  /** Render the top-right close control (default true). */
  showClose?: boolean
}) {
  return (
    <SheetPrimitive.Portal>
      <SheetPrimitive.Backdrop
        data-slot="sheet-backdrop"
        className={cn(
          "fixed inset-0 z-50 bg-overlay transition-opacity duration-180 ease-standard",
          "data-ending-style:opacity-0 data-starting-style:opacity-0"
        )}
      />
      <SheetPrimitive.Popup
        data-slot="sheet-content"
        data-side={side}
        className={cn(
          "fixed z-50 flex flex-col overflow-y-auto border-border bg-surface-raised p-5 text-foreground shadow-xl transition-[translate] duration-280 ease-standard outline-none light:[&>[data-slot=card-brackets]]:hidden",
          sideClasses[side],
          className
        )}
        {...props}
      >
        <CardBrackets />
        {showClose && (
          <SheetPrimitive.Close
            data-slot="sheet-close-x"
            aria-label="Close"
            className="absolute top-3 right-3 flex size-7 items-center justify-center text-muted-foreground transition-colors duration-120 ease-standard outline-none hover:bg-neutral-surface hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring"
          >
            <Icon name="close-line" className="text-[1rem]" />
          </SheetPrimitive.Close>
        )}
        {children}
      </SheetPrimitive.Popup>
    </SheetPrimitive.Portal>
  )
}

export function SheetHeader({
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
      data-slot="sheet-header"
      className={cn("mb-4 flex min-w-0 flex-col gap-1", className)}
      {...props}
    >
      {label != null && (
        <span className="scout-label [overflow-wrap:anywhere]">{label}</span>
      )}
      {title != null && <SheetTitle>{title}</SheetTitle>}
      {children}
    </div>
  )
}

export function SheetTitle({
  className,
  ...props
}: SheetPrimitive.Title.Props) {
  return (
    <SheetPrimitive.Title
      data-slot="sheet-title"
      className={cn("font-display text-lg [overflow-wrap:anywhere]", className)}
      {...props}
    />
  )
}

export function SheetDescription({
  className,
  ...props
}: SheetPrimitive.Description.Props) {
  return (
    <SheetPrimitive.Description
      data-slot="sheet-description"
      className={cn("text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

export function SheetFooter({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="sheet-footer"
      className={cn("mt-auto flex justify-end gap-2 pt-5", className)}
      {...props}
    />
  )
}

export function SheetClose(props: SheetPrimitive.Close.Props) {
  return <SheetPrimitive.Close data-slot="sheet-close" {...props} />
}
