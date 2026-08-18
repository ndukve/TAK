import { Toggle as TogglePrimitive } from "@base-ui/react/toggle"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

/**
 * Scout Toggle — a ghost button that latches. Use for standalone on/off
 * modes that act on the view (follow live tail, pin a panel); the pressed
 * state fills with primary/25 like a ToggleGroup segment. For settings
 * that persist, prefer Switch.
 */
const toggleVariants = cva(
  "inline-flex shrink-0 items-center justify-center gap-1.5 border border-transparent font-sans font-semibold whitespace-nowrap text-muted-foreground transition-colors duration-120 ease-standard outline-none select-none hover:bg-neutral-surface hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring data-pressed:bg-primary/25 data-pressed:text-foreground data-disabled:pointer-events-none data-disabled:opacity-45 [&_i[class^='ri-']]:text-[1em] [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      size: {
        sm: "h-7 px-2 text-xs",
        default: "h-9 px-2.5 text-sm",
        lg: "h-11 px-3 text-base",
      },
    },
    defaultVariants: {
      size: "default",
    },
  }
)

function Toggle({
  className,
  size = "default",
  ...props
}: TogglePrimitive.Props & VariantProps<typeof toggleVariants>) {
  return (
    <TogglePrimitive
      data-slot="toggle"
      className={cn(toggleVariants({ size, className }))}
      {...props}
    />
  )
}

export { Toggle, toggleVariants }
