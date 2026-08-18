import { Avatar as AvatarPrimitive } from "@base-ui/react/avatar"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

/**
 * Scout Avatar — square operator/node identity chip (radius is 0
 * everywhere, avatars included). Fallback renders mono uppercase
 * initials on the neutral surface. Sizes: sm 24px, default 28px,
 * lg 36px.
 */
const avatarVariants = cva(
  // Opaque surface: overlapping avatars (stacked groups) must fully cover
  // whatever sits beneath — alpha fills reveal the overlap as a bright seam.
  "relative flex shrink-0 overflow-hidden border border-border bg-surface-raised select-none",
  {
    variants: {
      size: {
        sm: "size-6 text-2xs",
        default: "size-7 text-2xs",
        lg: "size-9 text-xs",
      },
    },
    defaultVariants: {
      size: "default",
    },
  }
)

export function Avatar({
  className,
  size = "default",
  ...props
}: AvatarPrimitive.Root.Props & VariantProps<typeof avatarVariants>) {
  return (
    <AvatarPrimitive.Root
      data-slot="avatar"
      data-size={size}
      className={cn(avatarVariants({ size }), className)}
      {...props}
    />
  )
}

export function AvatarImage({
  className,
  ...props
}: AvatarPrimitive.Image.Props) {
  return (
    <AvatarPrimitive.Image
      data-slot="avatar-image"
      className={cn("aspect-square size-full object-cover", className)}
      {...props}
    />
  )
}

export function AvatarFallback({
  className,
  ...props
}: AvatarPrimitive.Fallback.Props) {
  return (
    <AvatarPrimitive.Fallback
      data-slot="avatar-fallback"
      className={cn(
        "flex size-full items-center justify-center font-mono tracking-wide text-muted-foreground uppercase",
        className
      )}
      {...props}
    />
  )
}
