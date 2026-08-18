import { Switch as SwitchPrimitive } from "@base-ui/react/switch"

import { cn } from "@/lib/utils"

/**
 * Scout Switch — mechanical on/off toggle with a square thumb. Use for
 * settings that apply immediately; the checked track fills with the
 * primary action color.
 */
export function Switch({ className, ...props }: SwitchPrimitive.Root.Props) {
  return (
    <SwitchPrimitive.Root
      data-slot="switch"
      className={cn(
        "inline-flex h-5 w-9 shrink-0 items-center border border-border bg-neutral-surface p-px transition-colors duration-120 ease-standard outline-none",
        "focus-visible:ring-3 focus-visible:ring-ring",
        "data-checked:border-primary data-checked:bg-primary",
        "data-disabled:pointer-events-none data-disabled:opacity-45",
        className
      )}
      {...props}
    >
      <SwitchPrimitive.Thumb
        data-slot="switch-thumb"
        className="block size-3.5 bg-muted-foreground transition-transform duration-120 ease-standard data-checked:translate-x-4.5 data-checked:bg-primary-foreground"
      />
    </SwitchPrimitive.Root>
  )
}
