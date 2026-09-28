import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { formatDay, formatWhen, formatSecondsLeft } from './attemptFormat'

describe('attemptFormat', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 8, 28, 15, 0))
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('names today as 今天 and other days by month and date', () => {
    expect(formatDay(new Date(2026, 8, 28, 9, 5))).toBe('今天')
    expect(formatDay(new Date(2026, 8, 26, 9, 5))).toBe('9 月 26 日')
  })

  it('adds a zero-padded 24-hour time', () => {
    expect(formatWhen(new Date(2026, 8, 28, 9, 5).toISOString())).toBe('今天 09:05')
    expect(formatWhen(new Date(2026, 8, 26, 0, 30).toISOString())).toBe('9 月 26 日 00:30')
  })

  it('returns an empty string for a missing or invalid date', () => {
    expect(formatWhen(null)).toBe('')
    expect(formatWhen('not a date')).toBe('')
  })

  it('shows whole minutes, or seconds under a minute', () => {
    expect(formatSecondsLeft(1500)).toBe('25 分鐘')
    expect(formatSecondsLeft(119)).toBe('1 分鐘')
    expect(formatSecondsLeft(40)).toBe('40 秒')
  })
})
