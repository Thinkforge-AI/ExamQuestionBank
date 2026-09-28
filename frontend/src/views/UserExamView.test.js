import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'

vi.mock('@/services/examService', () => ({
  default: {
    getMyExams: vi.fn(),
    abandonExamAttempt: vi.fn(),
    deleteExam: vi.fn(),
    getPracticeExams: vi.fn(),
    getExam: vi.fn()
  }
}))

import examService from '@/services/examService'
import UserExamView from './UserExamView.vue'

const hoursAgo = (h) => new Date(Date.now() - h * 3_600_000).toISOString()

const exam = (overrides) => ({
  id: 1,
  name: '民法總則　自訂練習卷',
  description: null,
  time_limit: 60,
  publish: false,
  created_at: hoursAgo(72),
  is_owner: true,
  question_count: 50,
  open_attempt: null,
  last_result: null,
  ...overrides
})

const TOOK = exam({
  id: 2, name: '113 年律師第一試　綜合法學（一）', is_owner: false, question_count: 75, time_limit: 120, created_at: hoursAgo(48),
  last_result: { id: 9, correct_count: 52, total_count: 75, score: 69, duration_seconds: 6240, completed_at: hoursAgo(5) }
})
const DOING = exam({
  id: 3, name: '113 年司法官第一試　民法', is_owner: false, question_count: 60, time_limit: 90, created_at: hoursAgo(24),
  open_attempt: { id: 'att-3', answered_count: 23, question_count: 60, flagged_count: 3, current_position: 24,
    elapsed_seconds: 32 * 60, time_limit_seconds: 90 * 60, updated_at: hoursAgo(1) }
})
const OWN = exam({})

describe('UserExamView (我的考卷)', () => {
  let router
  let wrapper

  const mountView = async () => {
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/user-exam', component: UserExamView },
        { path: '/exams/:id/preview', component: { template: '<div />' } },
        { path: '/exams/create', component: { template: '<div />' } },
        { path: '/admin/exams/:id/print', component: { template: '<div />' } }
      ]
    })
    await router.push('/user-exam')
    await router.isReady()
    wrapper = mount(UserExamView, { global: { plugins: [createPinia(), router] }, attachTo: document.body })
    await flushPromises()
    return wrapper
  }

  const button = (text) => wrapper.findAll('button').find((b) => b.text().includes(text))
  const rowNames = () => wrapper.findAll('.row-name').map((n) => n.text())

  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
    examService.getMyExams.mockResolvedValue({ data: [OWN, TOOK, DOING] })
    examService.abandonExamAttempt.mockResolvedValue({ data: null })
    examService.deleteExam.mockResolvedValue({ data: null })
  })

  afterEach(() => wrapper?.unmount())

  describe('spotlight', () => {
    it('puts the unfinished attempt first', async () => {
      await mountView()
      const spot = wrapper.find('.spotlight').text()
      expect(spot).toContain('還沒寫完')
      expect(spot).toContain('113 年司法官第一試　民法')
      expect(spot).toContain('23')
      expect(spot).toContain('/ 60')
      expect(spot).toContain('還剩 58 分鐘')
      expect(spot).toContain('3 題標記待複查')
      expect(button('繼續作答（從第 24 題）')).toBeTruthy()
    })

    it('continues the attempt on the exam page', async () => {
      await mountView()
      await button('繼續作答（從第 24 題）').trigger('click')
      await flushPromises()
      expect(router.currentRoute.value.path).toBe('/exams/3/preview')
    })

    it('shows the last exam practised when nothing is unfinished', async () => {
      examService.getMyExams.mockResolvedValue({ data: [OWN, TOOK] })
      await mountView()
      const spot = wrapper.find('.spotlight').text()
      expect(spot).toContain('上次練習的考卷')
      expect(spot).toContain('52')
      expect(spot).toContain('答對 69%')
      expect(spot).toContain('用時 104 分鐘')
    })

    it('has no spotlight before anything was taken', async () => {
      examService.getMyExams.mockResolvedValue({ data: [OWN] })
      await mountView()
      expect(wrapper.find('.spotlight').exists()).toBe(false)
    })
  })

  describe('list', () => {
    it('shows each exam\'s state', async () => {
      await mountView()
      const rows = wrapper.findAll('.exam-row')
      expect(rows[0].text()).toContain('寫到第 24 / 60 題')
      expect(rows[0].text()).toContain('繼續作答')
      expect(rows[1].text()).toContain('52 / 75（69%）')
      expect(rows[2].text()).toContain('還沒作答')
      expect(rows[2].text()).toContain('開始作答')
    })

    it('only offers delete on exams the user owns', async () => {
      await mountView()
      const deletable = wrapper.findAll('button[aria-label^="刪除"]').map((b) => b.attributes('aria-label'))
      expect(deletable).toEqual(['刪除「民法總則　自訂練習卷」'])
    })

    it('sorts by name and by latest activity', async () => {
      await mountView()
      expect(rowNames()).toEqual(['113 年司法官第一試　民法', '113 年律師第一試　綜合法學（一）', '民法總則　自訂練習卷'])

      await wrapper.find('.sort select').setValue('activity')
      expect(rowNames()[0]).toBe('113 年司法官第一試　民法') // touched 1 h ago
      expect(rowNames()[1]).toBe('113 年律師第一試　綜合法學（一）') // 5 h ago

      await wrapper.find('.sort select').setValue('name')
      expect(rowNames()).toEqual([...rowNames()].sort((a, b) => a.localeCompare(b, 'zh-Hant')))
    })
  })

  describe('confirmations', () => {
    it('deletes an owned exam after confirming', async () => {
      await mountView()
      await wrapper.find('button[aria-label="刪除「民法總則　自訂練習卷」"]').trigger('click')
      expect(wrapper.text()).toContain('刪除這份考卷？')
      expect(examService.deleteExam).not.toHaveBeenCalled()

      examService.getMyExams.mockResolvedValue({ data: [TOOK, DOING] })
      await button('刪除考卷').trigger('click')
      await flushPromises()

      expect(examService.deleteExam).toHaveBeenCalledWith(1)
      expect(wrapper.text()).not.toContain('刪除這份考卷？')
      expect(rowNames()).not.toContain('民法總則　自訂練習卷')
    })

    it('abandons the unfinished attempt after confirming', async () => {
      await mountView()
      await button('放棄這次作答').trigger('click')
      expect(wrapper.text()).toContain('已作答的 23 題會清除')

      examService.getMyExams.mockResolvedValue({ data: [OWN, TOOK] })
      await button('放棄作答').trigger('click')
      await flushPromises()

      expect(examService.abandonExamAttempt).toHaveBeenCalledWith('att-3')
      expect(wrapper.find('.spotlight').text()).toContain('上次練習的考卷')
    })

    it('keeps the attempt and says why when abandoning fails', async () => {
      examService.abandonExamAttempt.mockRejectedValue(new Error('Network Error'))
      await mountView()
      await button('放棄這次作答').trigger('click')
      await button('放棄作答').trigger('click')
      await flushPromises()

      expect(wrapper.text()).toContain('作答沒有放棄')
      expect(wrapper.find('.spotlight').text()).toContain('還沒寫完')
    })
  })

  describe('states', () => {
    it('shows the empty state with ways to start', async () => {
      examService.getMyExams.mockResolvedValue({ data: [] })
      await mountView()
      expect(wrapper.text()).toContain('還沒有考卷')
      await button('建立第一份考卷').trigger('click')
      await flushPromises()
      expect(router.currentRoute.value.path).toBe('/exams/create')
    })

    it('offers to reload when loading fails', async () => {
      examService.getMyExams.mockRejectedValueOnce(new Error('Network Error'))
      await mountView()
      expect(wrapper.text()).toContain('考卷載入失敗')
      await button('重新載入').trigger('click')
      await flushPromises()
      expect(wrapper.findAll('.exam-row')).toHaveLength(3)
    })
  })

  describe('random mock exam', () => {
    beforeEach(() => {
      examService.getPracticeExams = vi.fn().mockResolvedValue({
        data: [{ id: 2, name: 'A', question_count: 3 }, { id: 3, name: 'B', question_count: 2 }, { id: 4, name: 'Empty', question_count: 0 }]
      })
      examService.getExam.mockImplementation((id) => Promise.resolve({
        data: { exam_questions: id === 2 ? [{ question: 11 }, { question: 12 }, { question: 13 }] : [{ question: 13 }, { question: 14 }] }
      }))
    })

    it('needs a source before drawing, and explains the pool', async () => {
      await mountView()
      await button('隨機模擬考').trigger('click')
      await flushPromises()

      expect(wrapper.findAll('.source')).toHaveLength(2) // exams without questions are left out
      expect(button('抽題並建立考卷').attributes('disabled')).toBeDefined()
      expect(wrapper.find('.mock-summary').text()).toBe('先選至少一份考卷。')

      await wrapper.findAll('.source input')[0].setValue(true)
      expect(wrapper.find('.mock-summary').text()).toContain('從 3 題中隨機抽 3 題（只有 3 題，全部都會抽到）')
      expect(button('抽題並建立考卷（3 題）').attributes('disabled')).toBeUndefined()
    })

    it('draws distinct questions and opens the create page with them', async () => {
      await mountView()
      await button('隨機模擬考').trigger('click')
      await flushPromises()
      await button('全選').trigger('click')
      await button('10 題').trigger('click')
      await button('抽題並建立考卷').trigger('click')
      await flushPromises()

      expect(router.currentRoute.value.path).toBe('/exams/create')
      const ids = router.currentRoute.value.query.preload_questions.split(',').map(Number)
      expect(ids.sort()).toEqual([11, 12, 13, 14]) // question 13 is in both exams: drawn once
    })
  })
})
