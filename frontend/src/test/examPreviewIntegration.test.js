/**
 * Integration tests for ExamPreviewView complete exam flow
 * Tests full exam taking workflow from start to results
 * Tests error scenarios and recovery
 * Tests state persistence and restoration
 * 
 * Requirements: All requirements from exam-preview-redesign spec
 */

import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { setActivePinia, createPinia } from 'pinia'
import { createRouter, createWebHistory } from 'vue-router'
import { useExamStore } from '@/stores/examStore'

// Mock services
vi.mock('@/services/examService', () => ({
  default: {
    getExam: vi.fn(),
    startExam: vi.fn(),
    saveExamResult: vi.fn(),
    addBookmark: vi.fn(),
    getExamAttempt: vi.fn(),
    startExamAttempt: vi.fn(),
    saveAttemptProgress: vi.fn(),
    abandonExamAttempt: vi.fn(),
    getCurrentUserId: vi.fn()
  }
}))

vi.mock('@/services/questionService', () => ({
  default: {
    getQuestion: vi.fn()
  }
}))

vi.mock('@/services/flashcardService', () => ({
  default: {
    createFlashcard: vi.fn()
  }
}))

import examService from '@/services/examService'
import questionService from '@/services/questionService'
import ExamPreviewView from '@/views/ExamPreviewView.vue'

// Mock exam data
const mockExam = {
  id: 1,
  name: 'Test Exam',
  description: 'A test exam for integration testing',
  time_limit: 30,
  exam_questions: [
    {
      id: 1,
      question: 101,
      order: 1,
      question_content: 'What is 2 + 2?',
      question_subject: 'Math',
      question_category: 'Basic'
    },
    {
      id: 2,
      question: 102,
      order: 2,
      question_content: 'What is the capital of France?',
      question_subject: 'Geography',
      question_category: 'Capitals'
    },
    {
      id: 3,
      question: 103,
      order: 3,
      question_content: 'What color is the sky?',
      question_subject: 'Science',
      question_category: 'Nature'
    }
  ]
}

const mockQuestionDetails = {
  101: {
    id: 101,
    content: 'What is 2 + 2?',
    options: [
      { id: 1, content: '3', is_correct: false },
      { id: 2, content: '4', is_correct: true },
      { id: 3, content: '5', is_correct: false }
    ]
  },
  102: {
    id: 102,
    content: 'What is the capital of France?',
    options: [
      { id: 4, content: 'London', is_correct: false },
      { id: 5, content: 'Paris', is_correct: true },
      { id: 6, content: 'Berlin', is_correct: false }
    ]
  },
  103: {
    id: 103,
    content: 'What color is the sky?',
    options: [
      { id: 7, content: 'Green', is_correct: false },
      { id: 8, content: 'Blue', is_correct: true },
      { id: 9, content: 'Red', is_correct: false }
    ]
  }
}

// Create router
const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/exam/:id', name: 'exam-preview', component: ExamPreviewView }
  ]
})

describe('ExamPreviewView Integration Tests', () => {
  let wrapper
  let pinia

  beforeEach(async () => {
    // Reset mocks
    vi.clearAllMocks()
    
    // Setup localStorage mock
    const localStorageMock = {
      store: {},
      getItem: vi.fn((key) => localStorageMock.store[key] || null),
      setItem: vi.fn((key, value) => { localStorageMock.store[key] = value }),
      removeItem: vi.fn((key) => { delete localStorageMock.store[key] }),
      clear: vi.fn(() => { localStorageMock.store = {} })
    }
    global.localStorage = localStorageMock
    
    // Setup navigator mock
    global.navigator = { onLine: true }
    
    // Setup Pinia
    pinia = createPinia()
    setActivePinia(pinia)
    
    // Setup default mock responses
    examService.getExam.mockResolvedValue({ data: mockExam })
    examService.startExam.mockResolvedValue({ data: { success: true } })
    examService.saveExamResult.mockResolvedValue({ data: { success: true } })
    examService.getExamAttempt.mockResolvedValue({ data: null })
    examService.startExamAttempt.mockResolvedValue({ data: { id: 'att-new' } })
    examService.saveAttemptProgress.mockResolvedValue({ data: {} })
    examService.abandonExamAttempt.mockResolvedValue({ data: null })
    examService.getCurrentUserId.mockResolvedValue('user-1')

    questionService.getQuestion.mockImplementation((id) => {
      return Promise.resolve({ data: mockQuestionDetails[id] })
    })
    
    // Navigate to exam route
    router.push('/exam/1')
    await router.isReady()
  })

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount()
    }
  })

  const mountComponent = async () => {
    wrapper = mount(ExamPreviewView, {
      global: {
        plugins: [pinia, router],
        stubs: {
          ErrorBoundary: {
            template: '<div><slot /></div>',
            methods: { reset: vi.fn() }
          }
        }
      }
    })
    await flushPromises()
    return wrapper
  }

  describe('Exam Loading', () => {
    it('should load exam data on mount', async () => {
      await mountComponent()
      
      expect(examService.getExam).toHaveBeenCalledWith('1')
      expect(wrapper.text()).toContain('Test Exam')
    })

    it('should display exam metadata correctly', async () => {
      await mountComponent()
      
      expect(wrapper.text()).toContain('Test Exam')
      expect(wrapper.text()).toContain('A test exam for integration testing')
    })

    it('should show loading state while fetching exam', async () => {
      examService.getExam.mockImplementation(() => new Promise(() => {}))
      
      wrapper = mount(ExamPreviewView, {
        global: {
          plugins: [pinia, router],
          stubs: {
            ErrorBoundary: {
              template: '<div><slot /></div>'
            }
          }
        }
      })
      
      // Component shows Chinese loading text
      expect(wrapper.text()).toContain('載入考卷中')
    })

    it('should display error message on load failure', async () => {
      examService.getExam.mockRejectedValue({ 
        response: { status: 404 } 
      })
      
      await mountComponent()
      
      expect(wrapper.text()).toContain('找不到此考卷')
    })

    it('should display network error message when offline', async () => {
      global.navigator = { onLine: false }
      examService.getExam.mockRejectedValue(new Error('Network Error'))
      
      await mountComponent()
      
      expect(wrapper.text()).toContain('無法連接到伺服器')
    })
  })

  describe('Exam Start Flow', () => {
    it('should start exam when start button is clicked', async () => {
      await mountComponent()
      
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      expect(startButton.exists()).toBe(true)
      
      await startButton.trigger('click')
      await flushPromises()
      
      expect(examService.startExam).toHaveBeenCalledWith(1)
    })

    it('should show testing interface after starting exam', async () => {
      await mountComponent()
      
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      await startButton.trigger('click')
      await flushPromises()
      
      expect(wrapper.find('.testing-interface').exists()).toBe(true)
    })

    it('should display first question after starting', async () => {
      await mountComponent()
      
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      await startButton.trigger('click')
      await flushPromises()
      
      expect(wrapper.text()).toContain('第 1 / 3 題')
    })
  })

  describe('Question Navigation', () => {
    beforeEach(async () => {
      await mountComponent()
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      await startButton.trigger('click')
      await flushPromises()
    })

    it('should navigate to next question', async () => {
      const nextButton = wrapper.find('button[aria-label="Next question"]')
      await nextButton.trigger('click')
      
      expect(wrapper.text()).toContain('第 2 / 3 題')
    })

    it('should navigate to previous question', async () => {
      // Go to question 2
      const nextButton = wrapper.find('button[aria-label="Next question"]')
      await nextButton.trigger('click')
      
      // Go back to question 1
      const prevButton = wrapper.find('button[aria-label="Previous question"]')
      await prevButton.trigger('click')
      
      expect(wrapper.text()).toContain('第 1 / 3 題')
    })

    it('should disable previous button on first question', async () => {
      const prevButton = wrapper.find('button[aria-label="Previous question"]')
      expect(prevButton.attributes('disabled')).toBeDefined()
    })

    it('should disable next button on last question', async () => {
      // Navigate to last question
      const nextButton = wrapper.find('button[aria-label="Next question"]')
      await nextButton.trigger('click')
      await nextButton.trigger('click')
      
      expect(nextButton.attributes('disabled')).toBeDefined()
    })
  })

  describe('Answer Selection', () => {
    beforeEach(async () => {
      await mountComponent()
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      await startButton.trigger('click')
      await flushPromises()
    })

    it('should allow selecting an answer', async () => {
      const options = wrapper.findAll('.option-item')
      if (options.length > 0) {
        await options[0].trigger('click')
        expect(options[0].classes()).toContain('selected')
      }
    })

    it('should preserve answers when navigating between questions', async () => {
      // Select answer on question 1
      const options = wrapper.findAll('.option-item')
      if (options.length > 0) {
        await options[0].trigger('click')
      }
      
      // Navigate to question 2 and back
      const nextButton = wrapper.find('button[aria-label="Next question"]')
      await nextButton.trigger('click')
      
      const prevButton = wrapper.find('button[aria-label="Previous question"]')
      await prevButton.trigger('click')
      
      // Check answer is still selected
      const optionsAfter = wrapper.findAll('.option-item')
      if (optionsAfter.length > 0) {
        expect(optionsAfter[0].classes()).toContain('selected')
      }
    })
  })

  describe('Exam Submission', () => {
    beforeEach(async () => {
      await mountComponent()
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      await startButton.trigger('click')
      await flushPromises()
      
      // Mock confirm dialog
      global.confirm = vi.fn(() => true)
    })

    it('should submit exam when submit button is clicked', async () => {
      const submitButton = wrapper.find('button[aria-label="Submit exam"]')
      await submitButton.trigger('click')
      await flushPromises()
      
      expect(examService.saveExamResult).toHaveBeenCalled()
    })

    it('should show results after submission', async () => {
      const submitButton = wrapper.find('button[aria-label="Submit exam"]')
      await submitButton.trigger('click')
      await flushPromises()
      
      expect(wrapper.find('.results-panel').exists()).toBe(true)
    })

    it('should display quiz message after submission', async () => {
      const submitButton = wrapper.find('button[aria-label="Submit exam"]')
      await submitButton.trigger('click')
      await flushPromises()
      
      expect(wrapper.text()).toContain('測驗已提交')
    })

    it('should handle submission failure gracefully', async () => {
      examService.saveExamResult.mockRejectedValue(new Error('Server error'))
      
      const submitButton = wrapper.find('button[aria-label="Submit exam"]')
      await submitButton.trigger('click')
      await flushPromises()
      
      // Should still show results even if save fails
      expect(wrapper.find('.results-panel').exists()).toBe(true)
    })
  })

  describe('State Persistence', () => {
    // An unfinished attempt on question 2 (id 102), with question 1 answered and 10 minutes used
    const saveUnfinishedAttempt = (overrides = {}) => {
      localStorage.store['exam-attempt:1'] = JSON.stringify({
        v: 1,
        examId: 1,
        answers: { 101: 2 },
        flagged: [102],
        currentQuestionId: 102,
        elapsedSeconds: 600,
        updatedAt: new Date().toISOString(),
        ...overrides
      })
    }

    const findButton = (text) => wrapper.findAll('button').find((b) => b.text().includes(text))

    it('should persist the attempt per exam', async () => {
      await mountComponent()
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      await startButton.trigger('click')
      await flushPromises()

      expect(localStorage.setItem).toHaveBeenCalledWith('exam-attempt:1', expect.any(String))
      const saved = JSON.parse(localStorage.store['exam-attempt:1'])
      expect(saved.elapsedSeconds).toBe(0)
      expect(saved.currentQuestionId).toBe(101)
    })

    it('should save answers by question id', async () => {
      await mountComponent()
      await wrapper.find('button[aria-label="Start exam"]').trigger('click')
      await flushPromises()
      wrapper.vm.userAnswers[0] = 2
      await wrapper.find('button[aria-label="Next question"]').trigger('click')

      const saved = JSON.parse(localStorage.store['exam-attempt:1'])
      expect(saved.answers).toEqual({ 101: 2 })
      expect(saved.currentQuestionId).toBe(102)
    })

    it('should ask before resuming instead of resuming silently', async () => {
      saveUnfinishedAttempt()
      await mountComponent()

      expect(wrapper.find('.testing-interface').exists()).toBe(false)
      expect(wrapper.text()).toContain('上次的作答還沒寫完')
      expect(wrapper.text()).toContain('1 / 3 題')
      expect(wrapper.text()).toContain('20 分鐘') // 30 min limit − 10 min used
      expect(wrapper.text()).toContain('第 2 題')
    })

    it('should continue from the saved question with the saved answers', async () => {
      saveUnfinishedAttempt()
      await mountComponent()

      await findButton('繼續作答').trigger('click')
      await flushPromises()

      expect(wrapper.find('.testing-interface').exists()).toBe(true)
      expect(wrapper.text()).toContain('第 2 / 3 題')
      expect(wrapper.vm.userAnswers).toEqual({ 0: 2 })
      expect(examService.startExam).not.toHaveBeenCalled()
    })

    it('should reopen the prompt from the start button after dismissing it', async () => {
      saveUnfinishedAttempt()
      await mountComponent()

      await findButton('先不要').trigger('click')
      expect(wrapper.text()).not.toContain('上次的作答還沒寫完')

      const startButton = wrapper.find('button[aria-label="Start exam"]')
      expect(startButton.text()).toBe('繼續上次的作答')
      await startButton.trigger('click')
      expect(wrapper.text()).toContain('上次的作答還沒寫完')
    })

    it('should confirm before clearing progress to start over', async () => {
      saveUnfinishedAttempt()
      await mountComponent()

      await findButton('重新開始').trigger('click')
      expect(wrapper.text()).toContain('清除進度並重新開始？')
      expect(localStorage.removeItem).not.toHaveBeenCalledWith('exam-attempt:1')

      await findButton('清除並重新開始').trigger('click')
      await flushPromises()

      expect(localStorage.removeItem).toHaveBeenCalledWith('exam-attempt:1')
      expect(wrapper.text()).toContain('第 1 / 3 題')
      expect(wrapper.vm.userAnswers).toEqual({})
    })

    it('should offer to grade an attempt whose time is used up', async () => {
      global.confirm = vi.fn(() => true)
      saveUnfinishedAttempt({ elapsedSeconds: 30 * 60 })
      await mountComponent()

      expect(wrapper.text()).toContain('上次作答的時間已經用完')
      expect(findButton('繼續作答')).toBeUndefined()

      await findButton('交卷').trigger('click')
      await flushPromises()

      expect(wrapper.find('.results-panel').exists()).toBe(true)
      expect(examService.saveExamResult).toHaveBeenCalled()
    })

    it('should clear the saved attempt on submission', async () => {
      await mountComponent()
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      await startButton.trigger('click')
      await flushPromises()

      global.confirm = vi.fn(() => true)
      const submitButton = wrapper.find('button[aria-label="Submit exam"]')
      await submitButton.trigger('click')
      await flushPromises()

      expect(localStorage.removeItem).toHaveBeenCalledWith('exam-attempt:1')
      expect(localStorage.store['exam-attempt:1']).toBeUndefined()
    })
  })

  describe('Server Sync', () => {
    const findButton = (text) => wrapper.findAll('button').find((b) => b.text().includes(text))
    const minutesAgo = (m) => new Date(Date.now() - m * 60_000).toISOString()

    // On question 3 with questions 1–2 answered and 5 minutes used, saved on another device
    const serverAttempt = (overrides = {}) => ({
      id: 'att-9',
      exam_id: 1,
      status: 'in_progress',
      answers: { 101: 2, 102: 5 },
      flagged: [],
      current_question_id: 103,
      elapsed_seconds: 300,
      time_limit_seconds: 1800,
      updated_at: minutesAgo(10),
      ...overrides
    })

    const hideTab = () => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' })
      document.dispatchEvent(new Event('visibilitychange'))
    }

    afterEach(() => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' })
    })

    it('offers an attempt saved on another device', async () => {
      examService.getExamAttempt.mockResolvedValue({ data: serverAttempt() })
      await mountComponent()

      const prompt = wrapper.find('.resume-modal').text()
      expect(prompt).toContain('2 / 3 題')
      expect(prompt).toContain('25 分鐘')
      expect(prompt).toContain('第 3 題')

      await findButton('繼續作答').trigger('click')
      await flushPromises()

      expect(wrapper.text()).toContain('第 3 / 3 題')
      expect(examService.startExamAttempt).not.toHaveBeenCalled()
      expect(examService.saveAttemptProgress).toHaveBeenCalledWith('att-9', expect.objectContaining({
        answers: { 101: 2, 102: 5 }, currentQuestionId: 103
      }), { keepalive: false })
    })

    it('drops this device\'s copy of an attempt that was finished elsewhere', async () => {
      localStorage.store['exam-attempt:1'] = JSON.stringify({
        v: 1, examId: 1, attemptId: 'att-old', userId: 'user-1', answers: { 101: 2 }, flagged: [],
        currentQuestionId: 102, elapsedSeconds: 60, updatedAt: minutesAgo(1)
      })
      await mountComponent()

      expect(wrapper.find('.resume-modal').exists()).toBe(false)
      expect(localStorage.store['exam-attempt:1']).toBeUndefined()
      expect(wrapper.find('button[aria-label="Start exam"]').text()).toBe('開始測驗')
    })

    it('prefers newer answers from this device but keeps the larger time used', async () => {
      examService.getExamAttempt.mockResolvedValue({ data: serverAttempt({ elapsed_seconds: 600, updated_at: minutesAgo(30) }) })
      localStorage.store['exam-attempt:1'] = JSON.stringify({
        v: 1, examId: 1, attemptId: 'att-9', userId: 'user-1', answers: { 101: 2, 102: 5, 103: 8 }, flagged: [],
        currentQuestionId: 103, elapsedSeconds: 120, updatedAt: minutesAgo(1)
      })
      await mountComponent()

      const prompt = wrapper.find('.resume-modal').text()
      expect(prompt).toContain('3 / 3 題')
      expect(prompt).toContain('20 分鐘') // 30 − max(10, 2)
    })

    it('ignores progress another account left on this browser', async () => {
      localStorage.store['exam-attempt:1'] = JSON.stringify({
        v: 1, examId: 1, attemptId: null, userId: 'someone-else', answers: { 101: 2 }, flagged: [],
        currentQuestionId: 101, elapsedSeconds: 60, updatedAt: minutesAgo(1)
      })
      await mountComponent()

      expect(wrapper.find('.resume-modal').exists()).toBe(false)
    })

    it('starts the attempt on the server and links the result on submit', async () => {
      global.confirm = vi.fn(() => true)
      await mountComponent()
      await wrapper.find('button[aria-label="Start exam"]').trigger('click')
      await flushPromises()

      expect(examService.startExamAttempt).toHaveBeenCalledWith(1)
      expect(JSON.parse(localStorage.store['exam-attempt:1']).attemptId).toBe('att-new')

      await wrapper.find('button[aria-label="Submit exam"]').trigger('click')
      await flushPromises()

      expect(examService.saveExamResult).toHaveBeenCalledWith(expect.objectContaining({ attempt_id: 'att-new' }))
    })

    it('sends progress right away when the tab is hidden', async () => {
      await mountComponent()
      await wrapper.find('button[aria-label="Start exam"]').trigger('click')
      await flushPromises()
      examService.saveAttemptProgress.mockClear()

      hideTab()
      await flushPromises()

      expect(examService.saveAttemptProgress).toHaveBeenCalledWith('att-new', expect.any(Object), { keepalive: true })
    })

    it('keeps progress on this device and says so when the server is unreachable', async () => {
      examService.startExamAttempt.mockRejectedValue(new Error('Network Error'))
      await mountComponent()
      await wrapper.find('button[aria-label="Start exam"]').trigger('click')
      await flushPromises()

      expect(wrapper.find('.testing-interface').exists()).toBe(true)
      expect(wrapper.text()).toContain('進度先存在這台裝置')
      expect(localStorage.store['exam-attempt:1']).toBeDefined()
    })

    it('closes the old attempt on the server before starting over', async () => {
      examService.getExamAttempt.mockResolvedValue({ data: serverAttempt() })
      await mountComponent()

      await findButton('重新開始').trigger('click')
      await findButton('清除並重新開始').trigger('click')
      await flushPromises()

      expect(examService.abandonExamAttempt).toHaveBeenCalledWith('att-9')
      expect(examService.startExamAttempt).toHaveBeenCalled()
      expect(examService.abandonExamAttempt.mock.invocationCallOrder[0])
        .toBeLessThan(examService.startExamAttempt.mock.invocationCallOrder[0])
      expect(wrapper.text()).toContain('第 1 / 3 題')
    })

    it('does not start over when the old attempt cannot be closed', async () => {
      examService.getExamAttempt.mockResolvedValue({ data: serverAttempt() })
      examService.abandonExamAttempt.mockRejectedValue(new Error('Network Error'))
      await mountComponent()

      await findButton('重新開始').trigger('click')
      await findButton('清除並重新開始').trigger('click')
      await flushPromises()

      expect(wrapper.text()).toContain('連不上伺服器，進度沒有清除')
      expect(wrapper.find('.testing-interface').exists()).toBe(false)
      expect(examService.startExamAttempt).not.toHaveBeenCalled()
    })
  })

  describe('Error Recovery', () => {
    it('should provide retry option on network error', async () => {
      examService.getExam.mockRejectedValue({ 
        response: { status: 500 } 
      })
      
      await mountComponent()
      
      const retryButton = wrapper.find('button[aria-label="Retry loading exam"]')
      expect(retryButton.exists()).toBe(true)
    })

    it('should retry loading exam when retry button is clicked', async () => {
      examService.getExam
        .mockRejectedValueOnce({ response: { status: 500 } })
        .mockResolvedValueOnce({ data: mockExam })
      
      await mountComponent()
      
      const retryButton = wrapper.find('button[aria-label="Retry loading exam"]')
      if (retryButton.exists()) {
        await retryButton.trigger('click')
        await flushPromises()
        
        expect(examService.getExam).toHaveBeenCalledTimes(2)
      }
    })
  })

  describe('Accessibility', () => {
    it('should have proper ARIA labels on interactive elements', async () => {
      await mountComponent()
      
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      expect(startButton.exists()).toBe(true)
      
      const backButton = wrapper.find('button[aria-label="Go back"]')
      expect(backButton.exists()).toBe(true)
    })

    it('should have proper role attributes on sections', async () => {
      await mountComponent()
      const startButton = wrapper.find('button[aria-label="Start exam"]')
      await startButton.trigger('click')
      await flushPromises()
      
      const testingInterface = wrapper.find('[role="main"]')
      expect(testingInterface.exists()).toBe(true)
    })
  })
})

describe('ExamStore Integration', () => {
  let store

  beforeEach(() => {
    setActivePinia(createPinia())
    store = useExamStore()
  })

  it('should calculate results correctly', () => {
    // Setup exam with questions
    store.exam = {
      id: '1',
      name: 'Test Exam',
      questions: [
        {
          id: '1',
          content: 'Question 1',
          options: [
            { id: 1, content: 'A', isCorrect: false },
            { id: 2, content: 'B', isCorrect: true }
          ]
        },
        {
          id: '2',
          content: 'Question 2',
          options: [
            { id: 3, content: 'C', isCorrect: true },
            { id: 4, content: 'D', isCorrect: false }
          ]
        }
      ]
    }
    
    store.startExam()
    
    // Answer first question correctly, second incorrectly
    store.selectAnswer(0, 2) // Correct
    store.selectAnswer(1, 4) // Incorrect
    
    const results = store.calculateExamResults()
    
    expect(results.correctCount).toBe(1)
    expect(results.totalCount).toBe(2)
    expect(results.percentage).toBe(50)
    expect(results.wrongQuestionIds).toContain('2')
  })

  it('should handle all correct answers', () => {
    store.exam = {
      id: '1',
      name: 'Test Exam',
      questions: [
        {
          id: '1',
          content: 'Question 1',
          options: [{ id: 1, content: 'A', isCorrect: true }]
        },
        {
          id: '2',
          content: 'Question 2',
          options: [{ id: 2, content: 'B', isCorrect: true }]
        }
      ]
    }
    
    store.startExam()
    store.selectAnswer(0, 1)
    store.selectAnswer(1, 2)
    
    const results = store.calculateExamResults()
    
    expect(results.correctCount).toBe(2)
    expect(results.percentage).toBe(100)
    expect(results.wrongQuestionIds).toHaveLength(0)
  })

  it('should handle no answers', () => {
    store.exam = {
      id: '1',
      name: 'Test Exam',
      questions: [
        {
          id: '1',
          content: 'Question 1',
          options: [{ id: 1, content: 'A', isCorrect: true }]
        }
      ]
    }
    
    store.startExam()
    // Don't answer any questions
    
    const results = store.calculateExamResults()
    
    expect(results.correctCount).toBe(0)
    expect(results.percentage).toBe(0)
    expect(results.wrongQuestionIds).toContain('1')
  })
})
