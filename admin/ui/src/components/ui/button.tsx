import { Button as ButtonPrimitive } from "@base-ui/react/button"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "group/button inline-flex shrink-0 items-center justify-center gap-2 border border-transparent font-sans font-semibold whitespace-nowrap transition-[background-color,border-color,color,opacity] duration-120 ease-standard outline-none select-none focus-visible:ring-3 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-45 aria-invalid:border-critical-border aria-invalid:ring-3 aria-invalid:ring-critical-surface [&_i[class^='ri-']]:text-[1em] [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default:
          "border-primary bg-primary text-primary-foreground hover:border-primary-hover hover:bg-primary-hover",
        secondary:
          "border-border bg-neutral-surface text-foreground hover:border-border-strong",
        outline:
          "border-border-strong bg-transparent text-foreground hover:bg-neutral-surface aria-expanded:bg-neutral-surface",
        ghost:
          "text-muted-foreground hover:bg-neutral-surface hover:text-foreground aria-expanded:bg-neutral-surface aria-expanded:text-foreground",
        destructive:
          "border-critical-border bg-critical-surface text-critical hover:bg-[color-mix(in_oklch,var(--critical-surface),var(--critical)_12%)] focus-visible:ring-critical-surface",
        link: "text-primary-emphasis underline-offset-4 hover:underline",
      },
      size: {
        sm: "h-7 px-2.5 text-xs",
        default: "h-9 px-3.5 text-sm",
        lg: "h-11 px-4.5 text-base",
        icon: "size-9 [&_i[class^='ri-']]:text-[1.05rem]",
        "icon-sm": "size-7",
      },
    },
    compoundVariants: [
      { variant: "link", size: "sm", className: "h-auto px-0" },
      { variant: "link", size: "default", className: "h-auto px-0" },
      { variant: "link", size: "lg", className: "h-auto px-0" },
    ],
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

function Button({
  className,
  variant = "default",
  size = "default",
  ...props
}: ButtonPrimitive.Props & VariantProps<typeof buttonVariants>) {
  return (
    <ButtonPrimitive
      data-slot="button"
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Button, buttonVariants }
