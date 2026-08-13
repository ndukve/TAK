/**
 * Reticle corners were retired with the modern-minimal surface system.
 *
 * Keep this compatibility component because routes still use it alongside
 * `hud-frame`; rendering nothing updates every panel without page churn.
 */
export function HudCorners() {
  return null
}
