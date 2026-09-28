import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { shallowMount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'

vi.mock('@/api/test/question', () => ({
  questionApi: { getQuestionDetail: vi.fn(), getQuestions: vi.fn().mockResolvedValue({ results: [], count: 0 }) }
}))
vi.mock('@/api/test/exam', () => ({ examApi: { getExamDetail: vi.fn() } }))
vi.mock('vue-chartjs', () => ({ Pie: { template: '<div />' } }))
vi.mock('@/composables/useSticky', async () => {
  const { ref } = await import('vue')
  return { useSticky: () => ({ isSticky: ref(false) }) }
})

import { questionApi } from '@/api/test/question'
import { useExamStore } from '@/stores/test/exam'
import ExamEditView from './ExamEditView.vue'

describe('ExamEditView: preloaded questions', () => {
  let wrapper

  const mountAt = async (url) => {
    const pinia = createPinia()
    setActivePinia(pinia)
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/exams/create', component: ExamEditView }]
    })
    await router.push(url)
    await router.isReady()
    wrapper = shallowMount(ExamEditView, { global: { plugins: [pinia, router] } })
    await flushPromises()
    return useExamStore()
  }

  beforeEach(() => {
    vi.clearAllMocks()
    vi.spyOn(window, 'alert').mockImplementation(() => {})
    questionApi.getQuestionDetail.mockImplementation((id) => Promise.resolve({ id, content: `Q${id}` }))
  })

  afterEach(() => wrapper?.unmount())

  it('fills a new exam with the questions in ?preload_questions, in order', async () => {
    const store = await mountAt('/exams/create?preload_questions=14,11,13')
    expect(store.examQuestions.map((q) => q.id)).toEqual([14, 11, 13])
    expect(store.hasChanges).toBe(true)
  })

  it('starts empty without the parameter', async () => {
    const store = await mountAt('/exams/create')
    expect(questionApi.getQuestionDetail).not.toHaveBeenCalled()
    expect(store.examQuestions).toEqual([])
  })

  it('says how many questions could not be loaded', async () => {
    questionApi.getQuestionDetail.mockImplementation((id) =>
      id === 11 ? Promise.reject(new Error('Network Error')) : Promise.resolve({ id, content: `Q${id}` }))
    const store = await mountAt('/exams/create?preload_questions=14,11,13')
    expect(store.examQuestions.map((q) => q.id)).toEqual([14, 13])
    expect(window.alert).toHaveBeenCalledWith('有 1 題載入失敗，沒有加入考卷。')
  })
})
