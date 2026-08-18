import { PreviewCard as PreviewCardPrimitive } from "@base-ui/react/preview-card"

import { cn } from "@/lib/utils"

/**
 * Scout HoverCard — passive preview that opens on hover/focus over an
 * identifier (a router id, a node, a digest) and shows last-known state.
 * Deliberately unbracketed: it is a glance, not an instrument panel.
 * Compose `<HoverCard>` → `<HoverCardTrigger>` + `<HoverCardContent>`.
 */
export function HoverCard(props: PreviewCardPrimitive.Root.Props) {
  return <PreviewCardPrimitive.Root data-slot="hover-card" {...props} />
}

export function HoverCardTrigger({
  delay = 500,
  ...props
}: PreviewCardPrimitive.Trigger.Props) {
  return (
    <PreviewCardPrimitive.Trigger
      data-slot="hover-card-trigger"
      delay={delay}
      {...props}
    />
  )
}

export function HoverCardContent({
  className,
  side = "bottom",
  align = "center",
  sideOffset = 8,
  ...props
}: PreviewCardPrimitive.Popup.Props & {
  side?: PreviewCardPrimitive.Positioner.Props["side"]
  align?: PreviewCardPrimitive.Positioner.Props["align"]
  sideOffset?: PreviewCardPrimitive.Positioner.Props["sideOffset"]
}) {
  return (
    <PreviewCardPrimitive.Portal>
      <PreviewCardPrimitive.Positioner
        side={side}
        align={align}
        sideOffset={sideOffset}
        className="z-50"
      >
        <PreviewCardPrimitive.Popup
          data-slot="hover-card-content"
          className={cn(
            "w-72 border border-border bg-surface-raised p-4 text-foreground shadow-lg transition-opacity duration-120 ease-standard outline-none",
            "data-ending-style:opacity-0 data-starting-style:opacity-0",
            className
          )}
          {...props}
        />
      </PreviewCardPrimitive.Positioner>
    </PreviewCardPrimitive.Portal>
  )
}
