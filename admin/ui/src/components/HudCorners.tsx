import { CardBrackets } from '@/components/ui/card'

// Thin wrapper over Scout's real CardBrackets (components/ui/card.tsx,
// vendored verbatim from packages/ui) — reticle corners were retired here
// before the real bracket motif was ported in; every route already renders
// <HudCorners /> inside a `.hud-frame` container, so wiring this one file
// restores brackets everywhere without touching call sites.
export function HudCorners() {
  return <CardBrackets />
}
