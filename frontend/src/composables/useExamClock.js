import { ref, computed, getCurrentScope, onScopeDispose } from 'vue'

/**
 * Counts how long the user has actually spent on an exam.
 *
 * Time only accumulates while the clock is running AND the page is visible:
 * switching tabs, minimising the window, leaving the page or closing it all
 * pause it. Elapsed time is measured from monotonic timestamps rather than by
 * counting interval ticks, so background-tab throttling can't skew it.
 *
 * `start(initialSeconds)` resumes from a saved amount, which is what makes an
 * interrupted exam continue with the same time left.
 */
export function useExamClock({
  tickMs = 1000,
  // A gap longer than this between two ticks while "visible" means the page was
  // frozen (e.g. the laptop slept without a visibilitychange); it isn't counted.
  maxGapMs = 5000,
  now = () => performance.now(),
  doc = typeof document !== 'undefined' ? document : null
} = {}) {
  const elapsedMs = ref(0)
  const running = ref(false)
  let markedAt = null
  let intervalId = null

  const isVisible = () => !doc || doc.visibilityState !== 'hidden'

  // Fold the time since the last mark into elapsedMs, then re-mark if still counting.
  const sync = () => {
    const t = now()
    if (markedAt !== null) {
      const delta = t - markedAt
      elapsedMs.value += delta > maxGapMs ? tickMs : Math.max(0, delta)
    }
    markedAt = running.value && isVisible() ? t : null
  }

  const onVisibilityChange = () => sync()

  const start = (initialSeconds = 0) => {
    elapsedMs.value = Math.max(0, Number(initialSeconds) || 0) * 1000
    running.value = true
    markedAt = null
    sync()
    if (intervalId === null) intervalId = setInterval(sync, tickMs)
    doc?.addEventListener('visibilitychange', onVisibilityChange)
  }

  const pause = () => {
    sync()
    running.value = false
    markedAt = null
    if (intervalId !== null) {
      clearInterval(intervalId)
      intervalId = null
    }
    doc?.removeEventListener('visibilitychange', onVisibilityChange)
  }

  if (getCurrentScope()) onScopeDispose(pause)

  return {
    elapsedSeconds: computed(() => Math.floor(elapsedMs.value / 1000)),
    running,
    start,
    pause,
    sync
  }
}
