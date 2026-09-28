import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { effectScope } from 'vue'
import { useExamClock } from './useExamClock'

// A fake document whose visibility the test controls.
const makeDoc = () => {
  const listeners = new Set()
  return {
    visibilityState: 'visible',
    addEventListener: (type, fn) => type === 'visibilitychange' && listeners.add(fn),
    removeEventListener: (type, fn) => listeners.delete(fn),
    setVisible(visible) {
      this.visibilityState = visible ? 'visible' : 'hidden'
      listeners.forEach((fn) => fn())
    },
    listenerCount: () => listeners.size
  }
}

describe('useExamClock', () => {
  let t
  let doc
  let scope
  let clock

  // Advance both the fake monotonic clock and the interval timers.
  const pass = (ms) => {
    t += ms
    vi.advanceTimersByTime(ms)
  }

  beforeEach(() => {
    vi.useFakeTimers()
    t = 0
    doc = makeDoc()
    scope = effectScope()
    clock = scope.run(() => useExamClock({ now: () => t, doc }))
  })

  afterEach(() => {
    scope.stop()
    vi.useRealTimers()
  })

  it('counts time while running and visible', () => {
    clock.start()
    pass(5000)
    expect(clock.elapsedSeconds.value).toBe(5)
  })

  it('continues from a saved amount', () => {
    clock.start(120)
    pass(3000)
    expect(clock.elapsedSeconds.value).toBe(123)
  })

  it('does not count while the tab is hidden', () => {
    clock.start()
    pass(4000)
    doc.setVisible(false)
    pass(60_000)
    expect(clock.elapsedSeconds.value).toBe(4)
    doc.setVisible(true)
    pass(2000)
    expect(clock.elapsedSeconds.value).toBe(6)
  })

  it('does not count after pause, and pause keeps the partial second', () => {
    clock.start()
    pass(2500)
    clock.pause()
    pass(10_000)
    expect(clock.elapsedSeconds.value).toBe(2)
    clock.start(2.5)
    pass(600) // between ticks: sync() folds the partial time in
    clock.sync()
    expect(clock.elapsedSeconds.value).toBe(3)
  })

  it('ignores a long freeze while visible (e.g. the laptop slept)', () => {
    clock.start()
    pass(3000)
    t += 45 * 60 * 1000 // time jumps with no ticks in between
    vi.advanceTimersByTime(1000)
    expect(clock.elapsedSeconds.value).toBeLessThanOrEqual(4)
  })

  it('does not count when started while hidden', () => {
    doc.setVisible(false)
    clock.start()
    pass(10_000)
    expect(clock.elapsedSeconds.value).toBe(0)
  })

  it('removes its listener when the scope is disposed', () => {
    clock.start()
    expect(doc.listenerCount()).toBe(1)
    scope.stop()
    expect(doc.listenerCount()).toBe(0)
  })
})
