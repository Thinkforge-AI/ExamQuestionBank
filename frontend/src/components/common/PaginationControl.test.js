import { describe, it, expect } from 'vitest'
import { fc, test } from '@fast-check/vitest'
import { mount } from '@vue/test-utils'
import PaginationControl from './PaginationControl.vue'
import { buildPageWindow, PAGE_WINDOW_SLOTS } from '@/lib/pageWindow'

const state = (totalPages, totalCount = totalPages * 20) => ({
  totalPages,
  totalCount,
  hasPrev: false,
  hasNext: false
})

const mountAt = (currentPage, totalPages, extra = {}) =>
  mount(PaginationControl, {
    props: { paginationState: state(totalPages), currentPage, pageSize: 20, ...extra }
  })

describe('buildPageWindow', () => {
  it('lists every page when they fit', () => {
    expect(buildPageWindow(1, 1)).toEqual([1])
    expect(buildPageWindow(3, 7)).toEqual([1, 2, 3, 4, 5, 6, 7])
  })

  it('returns nothing for an empty result set', () => {
    expect(buildPageWindow(1, 0)).toEqual([])
  })

  it('handles the start, middle and end of a long list', () => {
    expect(buildPageWindow(1, 833)).toEqual([1, 2, 3, 4, 5, null, 833])
    expect(buildPageWindow(500, 833)).toEqual([1, null, 499, 500, 501, null, 833])
    expect(buildPageWindow(833, 833)).toEqual([1, null, 829, 830, 831, 832, 833])
  })

  it('clamps an out-of-range current page', () => {
    expect(buildPageWindow(9999, 20)).toEqual(buildPageWindow(20, 20))
    expect(buildPageWindow(-3, 20)).toEqual(buildPageWindow(1, 20))
  })

  test.prop([fc.integer({ min: 8, max: 5000 }).chain((total) =>
    fc.tuple(fc.constant(total), fc.integer({ min: 1, max: total }))
  )])('keeps a fixed width, the current page, both ends, and real gaps', ([total, current]) => {
    const pages = buildPageWindow(current, total)
    expect(pages).toHaveLength(PAGE_WINDOW_SLOTS)
    expect(pages).toContain(current)
    expect(pages[0]).toBe(1)
    expect(pages[pages.length - 1]).toBe(total)

    const numbers = pages.filter((p) => p !== null)
    expect(new Set(numbers).size).toBe(numbers.length)
    for (let i = 1; i < pages.length; i++) {
      const prev = pages[i - 1]
      const next = pages[i]
      if (next === null) {
        // A gap must hide at least two pages, otherwise that page should be shown.
        expect(pages[i + 1] - prev).toBeGreaterThanOrEqual(3)
      } else if (prev !== null) {
        expect(next).toBe(prev + 1)
      }
    }
  })
})

describe('PaginationControl', () => {
  it('marks only the current page with aria-current', () => {
    const wrapper = mountAt(500, 833)
    const current = wrapper.findAll('[aria-current="page"]')
    expect(current).toHaveLength(1)
    expect(current[0].text()).toBe('500')
  })

  it('renders gaps as non-interactive text, not buttons', () => {
    const wrapper = mountAt(500, 833)
    expect(wrapper.findAll('.page-gap')).toHaveLength(2)
    const pageButtons = wrapper.findAll('.pagination button').map((b) => b.text())
    expect(pageButtons).not.toContain('…')
  })

  it('does not render hundreds of links for a large result set', () => {
    const wrapper = mountAt(1, 10000)
    // 7 page slots (5 numbers + 1 gap + last) + first/prev/next/last
    expect(wrapper.findAll('.pagination button').length).toBeLessThanOrEqual(PAGE_WINDOW_SLOTS + 4)
  })

  it('gives the arrow buttons accessible names and disables them at the ends', () => {
    const first = mountAt(1, 10)
    expect(first.find('[aria-label="上一頁"]').attributes('disabled')).toBeDefined()
    expect(first.find('[aria-label="第一頁"]').attributes('disabled')).toBeDefined()
    expect(first.find('[aria-label="下一頁"]').attributes('disabled')).toBeUndefined()

    const last = mountAt(10, 10)
    expect(last.find('[aria-label="下一頁"]').attributes('disabled')).toBeDefined()
    expect(last.find('[aria-label="最後一頁"]').attributes('disabled')).toBeDefined()
  })

  it('emits the neighbouring page from prev/next', async () => {
    const wrapper = mountAt(5, 10)
    await wrapper.find('[aria-label="下一頁"]').trigger('click')
    await wrapper.find('[aria-label="上一頁"]').trigger('click')
    expect(wrapper.emitted('page-change')).toEqual([[6], [4]])
  })

  it('does not emit while loading or for the page already shown', async () => {
    const loading = mountAt(5, 10, { isLoading: true })
    await loading.find('[aria-label="下一頁"]').trigger('click')
    expect(loading.emitted('page-change')).toBeUndefined()

    const idle = mountAt(5, 10)
    await idle.find('[aria-current="page"]').trigger('click')
    expect(idle.emitted('page-change')).toBeUndefined()
  })

  it('shows an out-of-range page as the last real page', () => {
    const wrapper = mountAt(99, 10)
    expect(wrapper.find('[aria-current="page"]').text()).toBe('10')
    expect(wrapper.text()).toContain('第 10 / 10 頁')
  })

  it('labels the page-jump field and jumps on submit', async () => {
    const wrapper = mountAt(1, 50)
    const input = wrapper.find('.page-jumper input')
    const label = wrapper.find('.page-jumper label')
    expect(label.attributes('for')).toBe(input.attributes('id'))

    await input.setValue(42)
    await wrapper.find('.page-jumper').trigger('submit')
    expect(wrapper.emitted('page-change')).toEqual([[42]])
  })

  it('ignores a jump to a page that does not exist', async () => {
    const wrapper = mountAt(1, 50)
    await wrapper.find('.page-jumper input').setValue(51)
    await wrapper.find('.page-jumper').trigger('submit')
    expect(wrapper.emitted('page-change')).toBeUndefined()
  })
})
