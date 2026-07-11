import ms from 'milsymbol'

// CoT atom types (a-<affiliation>-<dimension>-<function...>) already use the
// same single-letter affiliation/battle-dimension vocabulary as MIL-STD-2525C
// SIDC positions 2-3, and the remaining dash-separated segments concatenate
// directly into the SIDC function-ID field (positions 5-10) — confirmed
// against milsymbol's own icon tables (e.g. CoT "a-h-A-M-F-Q" -> SIDC
// function-ID "MFQ---" -> milsymbol's "UNMANNED AERIAL VEHICLE" icon).
const _AFFILIATION_LETTERS = new Set(['F', 'H', 'N', 'U', 'A', 'S', 'G', 'W', 'D', 'L', 'M', 'J', 'K'])
const _DIMENSION_LETTERS = new Set(['P', 'A', 'G', 'S', 'U', 'F'])

export function cotTypeToSidc(cotType: string): string | null {
  const parts = cotType.split('-')
  if (parts[0] !== 'a' || parts.length < 3) return null
  const affiliation = parts[1]?.toUpperCase()
  const dimension = parts[2]?.toUpperCase()
  if (!affiliation || !_AFFILIATION_LETTERS.has(affiliation)) return null
  if (!dimension || !_DIMENSION_LETTERS.has(dimension)) return null
  const functionId = parts.slice(3).join('').toUpperCase().padEnd(6, '-').slice(0, 6)
  return `S${affiliation}${dimension}P${functionId}------`
}

export interface CotSymbol {
  svg: string
  width: number
  height: number
  anchorX: number
  anchorY: number
}

const _cache = new Map<string, CotSymbol | null>()

// Renders a CoT type to a MIL-STD-2525C symbol (affiliation frame + function
// glyph — e.g. a hostile UAV renders as the standard red diamond with the
// UAV icon inside, matching how ATAK itself renders the same CoT type).
// Returns null for non-atom types or anything milsymbol can't resolve —
// callers should fall back to a generic marker in that case.
export function renderCotSymbol(cotType: string, size = 28): CotSymbol | null {
  const sidc = cotTypeToSidc(cotType)
  if (!sidc) return null
  const cacheKey = `${sidc}:${size}`
  if (_cache.has(cacheKey)) return _cache.get(cacheKey) ?? null
  let result: CotSymbol | null
  try {
    const sym = new ms.Symbol(sidc, { size })
    const { width, height } = sym.getSize()
    const { x, y } = sym.getAnchor()
    result = { svg: sym.asSVG(), width, height, anchorX: x, anchorY: y }
  } catch {
    result = null
  }
  _cache.set(cacheKey, result)
  return result
}
