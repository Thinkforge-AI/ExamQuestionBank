import { describe, it, expect, beforeEach } from 'vitest'
import { loadAttempt, saveAttempt, clearAttempt, fromServerAttempt } from './examAttemptStorage'

const QUESTIONS = [101, 102, 103, 104]

describe('examAttemptStorage', () => {
  beforeEach(() => {
    // The global test setup stubs localStorage with no-op mocks; use a working one here.
    const store = new Map()
    global.localStorage = {
      getItem: (key) => (store.has(key) ? store.get(key) : null),
      setItem: (key, value) => store.set(key, String(value)),
      removeItem: (key) => store.delete(key),
      clear: () => store.clear()
    }
  })

  it('returns null when nothing is saved', () => {
    expect(loadAttempt(1, QUESTIONS)).toBeNull()
  })

  it('round-trips answers, flags, position and time', () => {
    saveAttempt(1, {
      questionIds: QUESTIONS,
      answers: { 0: 11, 2: 33 },
      flagged: new Set([2]),
      currentIndex: 3,
      elapsedSeconds: 754.9
    })
    const loaded = loadAttempt(1, QUESTIONS)
    expect(loaded.answers).toEqual({ 0: 11, 2: 33 })
    expect([...loaded.flagged]).toEqual([2])
    expect(loaded.currentIndex).toBe(3)
    expect(loaded.elapsedSeconds).toBe(754)
    expect(loaded.answeredCount).toBe(2)
    expect(typeof loaded.updatedAt).toBe('string')
  })

  it('keeps the time limit a server attempt started with', () => {
    const state = { questionIds: QUESTIONS, answers: {}, flagged: [], currentIndex: 0, elapsedSeconds: 0 }
    saveAttempt(1, { ...state, attemptId: 'att-1', timeLimitSeconds: 1800 })
    saveAttempt(2, { ...state, attemptId: 'att-2', timeLimitSeconds: null })
    saveAttempt(3, state)
    expect(loadAttempt(1, QUESTIONS).timeLimitSeconds).toBe(1800)
    expect(loadAttempt(2, QUESTIONS).timeLimitSeconds).toBeNull() // no limit
    expect(loadAttempt(3, QUESTIONS)).not.toHaveProperty('timeLimitSeconds') // no server attempt

    expect(fromServerAttempt({ id: 'att-1', time_limit_seconds: 1800 }, QUESTIONS).timeLimitSeconds).toBe(1800)
    expect(fromServerAttempt({ id: 'att-1', time_limit_seconds: null }, QUESTIONS).timeLimitSeconds).toBeNull()
  })

  it('keeps each exam separate', () => {
    saveAttempt(1, { questionIds: QUESTIONS, answers: { 0: 11 }, flagged: [], currentIndex: 0, elapsedSeconds: 10 })
    saveAttempt(2, { questionIds: QUESTIONS, answers: { 1: 22 }, flagged: [], currentIndex: 1, elapsedSeconds: 20 })
    expect(loadAttempt(1, QUESTIONS).answers).toEqual({ 0: 11 })
    expect(loadAttempt(2, QUESTIONS).answers).toEqual({ 1: 22 })
  })

  it('follows questions by id when the exam order changes', () => {
    saveAttempt(1, { questionIds: QUESTIONS, answers: { 0: 11, 3: 44 }, flagged: [3], currentIndex: 3, elapsedSeconds: 0 })
    const reordered = [104, 103, 102, 101]
    const loaded = loadAttempt(1, reordered)
    expect(loaded.answers).toEqual({ 3: 11, 0: 44 })
    expect([...loaded.flagged]).toEqual([0])
    expect(loaded.currentIndex).toBe(0)
  })

  it('drops answers for questions no longer in the exam', () => {
    saveAttempt(1, { questionIds: QUESTIONS, answers: { 0: 11, 1: 22 }, flagged: [], currentIndex: 1, elapsedSeconds: 0 })
    const loaded = loadAttempt(1, [101, 103])
    expect(loaded.answers).toEqual({ 0: 11 })
    expect(loaded.currentIndex).toBe(0)
  })

  it('does not expire', () => {
    localStorage.setItem('exam-attempt:1', JSON.stringify({
      v: 1, examId: 1, answers: { 101: 11 }, flagged: [], currentQuestionId: 101,
      elapsedSeconds: 30, updatedAt: '2026-01-01T00:00:00.000Z'
    }))
    expect(loadAttempt(1, QUESTIONS).answeredCount).toBe(1)
  })

  it('clears an attempt', () => {
    saveAttempt(1, { questionIds: QUESTIONS, answers: { 0: 11 }, flagged: [], currentIndex: 0, elapsedSeconds: 0 })
    clearAttempt(1)
    expect(loadAttempt(1, QUESTIONS)).toBeNull()
  })

  it('treats a corrupt entry as nothing saved', () => {
    localStorage.setItem('exam-attempt:1', '{not json')
    expect(loadAttempt(1, QUESTIONS)).toBeNull()
  })

  it('migrates the old single-slot entry into its exam, with the full time back', () => {
    localStorage.setItem('exam-preview-state', JSON.stringify({
      examId: 7, userAnswers: { 1: 22 }, currentQuestionIndex: 1, isQuizActive: true,
      startTime: Date.now() - 3_600_000, flaggedQuestions: [1], timestamp: new Date().toISOString()
    }))
    const loaded = loadAttempt(7, QUESTIONS)
    expect(loaded.answers).toEqual({ 1: 22 })
    expect([...loaded.flagged]).toEqual([1])
    expect(loaded.currentIndex).toBe(1)
    expect(loaded.elapsedSeconds).toBe(0)
    expect(localStorage.getItem('exam-preview-state')).toBeNull()
  })

  it('migrates the old entry even when another exam is opened first', () => {
    localStorage.setItem('exam-preview-state', JSON.stringify({
      examId: 7, userAnswers: { 0: 11 }, currentQuestionIndex: 0, isQuizActive: true, timestamp: new Date().toISOString()
    }))
    expect(loadAttempt(1, QUESTIONS)).toBeNull()
    expect(loadAttempt(7, QUESTIONS).answers).toEqual({ 0: 11 })
  })
})
