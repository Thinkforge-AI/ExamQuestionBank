import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

const rpc = vi.fn()
vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: (...args) => rpc(...args),
    auth: {
      getSession: () => Promise.resolve({ data: { session: { access_token: 'token' } } }),
      onAuthStateChange: () => {}
    }
  }
}))

const { default: examService } = await import('./examService')

const progress = { answers: { 101: 2 }, flagged: [], currentQuestionId: 101, elapsedSeconds: 30 }

describe('examService.saveAttemptProgress', () => {
  beforeEach(() => rpc.mockReset())
  afterEach(() => vi.unstubAllGlobals())

  it('sends the writer and whether it claims the attempt', async () => {
    rpc.mockResolvedValue({ data: {}, error: null })
    await examService.saveAttemptProgress('att-1', progress, { writerId: 'w-1', claim: true })
    expect(rpc).toHaveBeenCalledWith('save_attempt_progress', expect.objectContaining({
      p_attempt_id: 'att-1', p_writer_id: 'w-1', p_claim: true
    }))
  })

  it('marks a save refused because another page continued the attempt', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: 'PT409', message: 'Attempt is being continued elsewhere' } })
    await expect(examService.saveAttemptProgress('att-1', progress, { writerId: 'w-1' }))
      .rejects.toMatchObject({ conflict: true })

    rpc.mockResolvedValue({ data: null, error: { code: 'P0002', message: 'Attempt not found or already finished' } })
    await expect(examService.saveAttemptProgress('att-1', progress, { writerId: 'w-1' }))
      .rejects.toMatchObject({ conflict: false })
  })

  it('marks the same refusal on a keepalive save (HTTP 409)', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 409 }))
    await Promise.resolve() // let the cached access token load
    await expect(examService.saveAttemptProgress('att-1', progress, { writerId: 'w-1', keepalive: true }))
      .rejects.toMatchObject({ conflict: true })
    expect(fetch).toHaveBeenCalledWith(expect.stringContaining('/rpc/save_attempt_progress'),
      expect.objectContaining({ keepalive: true, body: expect.stringContaining('"p_writer_id":"w-1"') }))
  })
})
