/**
 * Unit tests for TimerComponent.
 * The component shows the time left from `timeLimit` and `elapsed`; the parent
 * owns the clock, so pausing and resuming are the parent's job.
 */

import { describe, it, expect, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import TimerComponent from './TimerComponent.vue'

describe('TimerComponent', () => {
  let wrapper

  afterEach(() => {
    wrapper?.unmount()
  })

  const mountAt = (timeLimit, elapsed = 0) => {
    wrapper = mount(TimerComponent, { props: { timeLimit, elapsed } })
    return wrapper
  }

  describe('display', () => {
    it('shows the time left as mm:ss', () => {
      mountAt(125)
      expect(wrapper.find('.timer-value').text()).toBe('02:05')
    })

    it('subtracts the time already used', () => {
      mountAt(90 * 60, 32 * 60 + 15)
      expect(wrapper.find('.timer-value').text()).toBe('57:45')
    })

    it('never shows a negative time', () => {
      mountAt(60, 500)
      expect(wrapper.find('.timer-value').text()).toBe('00:00')
    })

    it('updates when elapsed changes', async () => {
      mountAt(125)
      await wrapper.setProps({ elapsed: 5 })
      expect(wrapper.find('.timer-value').text()).toBe('02:00')
    })

    it('applies the normal, warning and danger states', async () => {
      mountAt(400)
      expect(wrapper.classes()).toContain('normal')
      await wrapper.setProps({ elapsed: 100 }) // 300 left
      expect(wrapper.classes()).toContain('warning')
      await wrapper.setProps({ elapsed: 340 }) // 60 left
      expect(wrapper.classes()).toContain('danger')
    })
  })

  describe('threshold events', () => {
    it('emits time-warning once when crossing 5 minutes', async () => {
      mountAt(310)
      await wrapper.setProps({ elapsed: 5 })
      expect(wrapper.emitted('time-warning')).toBeFalsy()
      await wrapper.setProps({ elapsed: 10 })
      expect(wrapper.emitted('time-warning')).toEqual([[300]])
      await wrapper.setProps({ elapsed: 11 })
      expect(wrapper.emitted('time-warning')).toHaveLength(1)
    })

    it('emits time-critical once when crossing 1 minute', async () => {
      mountAt(70)
      await wrapper.setProps({ elapsed: 10 })
      expect(wrapper.emitted('time-critical')).toEqual([[60]])
    })

    it('emits time-expired once when reaching zero', async () => {
      mountAt(3)
      await wrapper.setProps({ elapsed: 2 })
      expect(wrapper.emitted('time-expired')).toBeFalsy()
      await wrapper.setProps({ elapsed: 3 })
      expect(wrapper.emitted('time-expired')).toHaveLength(1)
      await wrapper.setProps({ elapsed: 4 })
      expect(wrapper.emitted('time-expired')).toHaveLength(1)
    })

    it('still emits when elapsed jumps past a threshold', async () => {
      mountAt(400)
      await wrapper.setProps({ elapsed: 395 })
      expect(wrapper.emitted('time-critical')).toEqual([[5]])
      expect(wrapper.emitted('time-warning')).toBeFalsy()
    })

    it('does not re-warn when mounted already past a threshold (resumed exam)', async () => {
      mountAt(3600, 3500) // 100 s left on mount
      await wrapper.setProps({ elapsed: 3501 })
      expect(wrapper.emitted('time-warning')).toBeFalsy()
      expect(wrapper.emitted('time-critical')).toBeFalsy()
    })

    it('does not emit time-expired when mounted with no time left', () => {
      mountAt(60, 60)
      expect(wrapper.emitted('time-expired')).toBeFalsy()
    })
  })
})
