import { Radio as RadioPrimitive } from "@base-ui/react/radio"
import { RadioGroup as RadioGroupPrimitive } from "@base-ui/react/radio-group"

import { cn } from "@/lib/utils"

/**
 * Scout RadioGroup — exclusive choice set. Square markers (no circles in
 * this system); the checked item carries a primary border and a filled
 * inner square. Compose each `<Radio>` with a plain `<label>`.
 */
export function RadioGroup({ className, ...props }: RadioGroupPrimitive.Props) {
  return (
    <RadioGroupPrimitive
      data-slot="radio-group"
      className={cn("flex flex-col gap-2.5", className)}
      {...props}
    />
  )
}

export function Radio({ className, ...props }: RadioPrimitive.Root.Props) {
  return (
    <RadioPrimitive.Root
      data-slot="radio"
      className={cn(
        "flex size-4 shrink-0 items-center justify-center border border-border-strong bg-surface-inset transition-[border-color] duration-120 ease-standard outline-none",
        "focus-visible:ring-3 focus-visible:ring-ring",
        "data-checked:border-primary",
        "data-disabled:pointer-events-none data-disabled:opacity-45",
        className
      )}
      {...props}
    >
      <RadioPrimitive.Indicator
        data-slot="radio-indicator"
        className="flex size-2 bg-primary"
      />
    </RadioPrimitive.Root>
  )
}
