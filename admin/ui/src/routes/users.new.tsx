import { createFileRoute, redirect, useNavigate } from '@tanstack/react-router'
import { useState } from 'react'
import { Layout } from '@/components/Layout'
import { apiJson } from '@/lib/api'
import { useAuth } from '@/store/auth'
import { toast } from 'sonner'
import { CheckCircle } from 'lucide-react'

export const Route = createFileRoute('/users/new')({
  beforeLoad: () => {
    const { token } = useAuth.getState()
    if (!token) throw redirect({ to: '/login' })
  },
  component: NewUserPage,
})

type Step = 'form' | 'gen-cert' | 'make-package' | 'enable' | 'done'

function NewUserPage() {
  const [username, setUsername] = useState('')
  const [step, setStep] = useState<Step>('form')
  const [downloadUrl, setDownloadUrl] = useState('')
  const navigate = useNavigate()

  async function runStep(nextStep: Step, endpoint: string, body: object) {
    setStep(nextStep)
    const data = await apiJson<any>(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    if (data.download_url) setDownloadUrl(data.download_url)
  }

  async function handleCreate() {
    if (!username.trim()) return
    try {
      await runStep('gen-cert', '/api/users/gen-cert', { username })
      await runStep('make-package', '/api/users/make-package', { username })
      await runStep('enable', '/api/users/enable', { username })
      setStep('done')
    } catch (e: any) {
      toast.error(e.message)
      setStep('form')
    }
  }

  const steps: { id: Step; label: string }[] = [
    { id: 'gen-cert', label: 'Generate device certificate' },
    { id: 'make-package', label: 'Build data package' },
    { id: 'enable', label: 'Authorize on server' },
  ]

  const stepOrder: Step[] = ['form', 'gen-cert', 'make-package', 'enable', 'done']

  return (
    <Layout>
      <div className="p-6 max-w-lg">
        <h1 className="text-xl font-semibold mb-6">New User</h1>

        {step === 'form' && (
          <div className="space-y-4">
            <div className="space-y-1">
              <label className="text-sm text-zinc-300">Callsign</label>
              <input
                type="text"
                value={username}
                onChange={e => setUsername(e.target.value.replace(/[^a-zA-Z0-9_-]/g, ''))}
                placeholder="e.g. alpha-1"
                className="w-full px-3 py-2 rounded-md bg-zinc-800 border border-zinc-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <p className="text-xs text-zinc-500">Letters, numbers, hyphens, underscores only.</p>
            </div>
            <button
              onClick={handleCreate}
              disabled={!username.trim()}
              className="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm rounded-md disabled:opacity-50 transition-colors"
            >
              Create
            </button>
          </div>
        )}

        {step !== 'form' && step !== 'done' && (
          <div className="space-y-3">
            {steps.map(s => {
              const idx = stepOrder.indexOf(s.id)
              const currentIdx = stepOrder.indexOf(step)
              const done = idx < currentIdx
              const active = s.id === step
              return (
                <div key={s.id} className={`flex items-center gap-3 p-3 rounded-lg border ${active ? 'border-blue-500 bg-blue-500/10' : done ? 'border-zinc-700 bg-zinc-900' : 'border-zinc-800 opacity-40'}`}>
                  {done ? <CheckCircle size={16} className="text-green-400 shrink-0" /> : <div className={`w-4 h-4 rounded-full border-2 shrink-0 ${active ? 'border-blue-400 animate-pulse' : 'border-zinc-600'}`} />}
                  <span className="text-sm">{s.label}</span>
                </div>
              )
            })}
          </div>
        )}

        {step === 'done' && (
          <div className="space-y-4">
            <div className="flex items-center gap-2 text-green-400">
              <CheckCircle size={18} />
              <span className="font-medium">{username} is ready</span>
            </div>
            {downloadUrl && (
              <a
                href={downloadUrl}
                className="inline-block px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-white text-sm rounded-md transition-colors"
              >
                Download data package
              </a>
            )}
            <button
              onClick={() => navigate({ to: '/packages' })}
              className="block px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-white text-sm rounded-md transition-colors"
            >
              View packages →
            </button>
          </div>
        )}
      </div>
    </Layout>
  )
}
