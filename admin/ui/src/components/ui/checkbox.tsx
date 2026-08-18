import { Checkbox as CheckboxPrimitive } from "@base-ui/react/checkbox"

import { cn } from "@/lib/utils"
import { Icon } from "@/components/ui/icon"

/**
 * Scout Checkbox — square tick box on the inset surface. Compose with a
 * plain `<label>` for the caption; checked state fills with the primary
 * action color.
 */
export function Checkbox({
  className,
  ...props
}: CheckboxPrimitive.Root.Props) {
  return (
    <CheckboxPrimitive.Root
      data-slot="checkbox"
      className={cn(
        "flex size-4 shrink-0 items-center justify-center border border-border-strong bg-surface-inset transition-[background-color,border-color] duration-120 ease-standard outline-none",
        "focus-visible:ring-3 focus-visible:ring-ring",
        "data-checked:border-primary data-checked:bg-primary",
        "data-disabled:pointer-events-none data-disabled:opacity-45",
        className
      )}
      {...props}
    >
      <CheckboxPrimitive.Indicator
        data-slot="checkbox-indicator"
        className="flex text-primary-foreground"
      >
        <Icon name="check-line" className="text-[0.75rem]" />
      </CheckboxPrimitive.Indicator>
    </CheckboxPrimitive.Root>
  )
}
