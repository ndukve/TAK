import { Status } from '@/components/ui/status'

// Thin wrapper over Scout's real Status component (components/ui/status.tsx,
// vendored verbatim from packages/ui) — keeps this file's existing
// ok/warn/bad call-site API so route files don't need touching.
const TONE = { ok: 'nominal', warn: 'warning', bad: 'critical' } as const

export function StatusPill({ text, tone }: { text: string; tone: 'ok' | 'warn' | 'bad' }) {
  return <Status tone={TONE[tone]}>{text}</Status>
}
