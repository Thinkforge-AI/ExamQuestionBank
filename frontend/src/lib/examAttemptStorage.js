/**
 * Local persistence for an unfinished exam attempt, one entry per exam.
 *
 * Answers and flags are stored by question id rather than position, so an
 * attempt still lines up if the exam's question order changes. Entries never
 * expire on their own: they are removed when the attempt is submitted,
 * abandoned or restarted.
 */

const KEY_PREFIX = 'exam-attempt:'
const LEGACY_KEY = 'exam-preview-state' // single-slot format used before per-exam storage
const VERSION = 1

const keyFor = (examId) => `${KEY_PREFIX}${examId}`

const read = (key) => {
  try {
    const raw = localStorage.getItem(key)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

const write = (key, value) => {
  try {
    localStorage.setItem(key, JSON.stringify(value))
    return true
  } catch {
    return false
  }
}

const remove = (key) => {
  try {
    localStorage.removeItem(key)
  } catch {
    // Storage unavailable: nothing to clean up.
  }
}

// Move a leftover single-slot entry into its exam's own key. The old format
// stored answers by position and measured wall-clock time, so the elapsed time
// can't be recovered: it restarts at 0 (the user gets the full time back).
const migrateLegacy = () => {
  const legacy = read(LEGACY_KEY)
  if (!legacy) return
  remove(LEGACY_KEY)
  if (!legacy.examId || !legacy.isQuizActive || read(keyFor(legacy.examId))) return
  write(keyFor(legacy.examId), {
    v: 0,
    examId: legacy.examId,
    answersByIndex: legacy.userAnswers || {},
    flaggedIndexes: legacy.flaggedQuestions || [],
    currentIndex: legacy.currentQuestionIndex || 0,
    elapsedSeconds: 0,
    updatedAt: legacy.timestamp || new Date().toISOString()
  })
}

// Map an attempt stored by question id onto the exam's current question order.
const byPosition = (questionIds, { answers = {}, flagged = [], currentQuestionId }) => {
  const indexOf = new Map(questionIds.map((id, i) => [String(id), i]))
  const positions = {}
  for (const [qid, option] of Object.entries(answers)) {
    if (indexOf.has(qid)) positions[indexOf.get(qid)] = option
  }
  const flaggedPositions = new Set()
  for (const qid of flagged) {
    if (indexOf.has(String(qid))) flaggedPositions.add(indexOf.get(String(qid)))
  }
  return {
    answers: positions,
    flagged: flaggedPositions,
    currentIndex: indexOf.get(String(currentQuestionId)) ?? 0,
    answeredCount: Object.keys(positions).length
  }
}

// Same shape as byPosition, for a migrated legacy (v0) entry, which is already by
// position: drop anything past the end of the exam's current questions.
const legacyByPosition = (questionIds, saved) => {
  const answers = {}
  for (const [i, option] of Object.entries(saved.answersByIndex || {})) {
    if (Number(i) < questionIds.length) answers[Number(i)] = option
  }
  return {
    answers,
    flagged: new Set((saved.flaggedIndexes || []).filter((i) => i < questionIds.length)),
    currentIndex: Math.min(saved.currentIndex || 0, Math.max(0, questionIds.length - 1)),
    answeredCount: Object.keys(answers).length
  }
}

/**
 * @param {number|string} examId
 * @param {Array<number>} questionIds question ids in the exam's current order
 * @returns {null | { answers: Record<number, number>, flagged: Set<number>, currentIndex: number,
 *   elapsedSeconds: number, updatedAt: string, answeredCount: number,
 *   attemptId: string|null, userId: string|null }}
 *   answers/flagged/currentIndex are by position in `questionIds`.
 */
export function loadAttempt(examId, questionIds) {
  migrateLegacy()
  const saved = read(keyFor(examId))
  if (!saved || !Array.isArray(questionIds)) return null

  return {
    ...(saved.v === 0 ? legacyByPosition(questionIds, saved) : byPosition(questionIds, saved)),
    elapsedSeconds: Math.max(0, Number(saved.elapsedSeconds) || 0),
    updatedAt: saved.updatedAt,
    attemptId: saved.attemptId || null,
    userId: saved.userId || null
  }
}

/**
 * Same shape as loadAttempt, from an exam_attempt row returned by the server.
 */
export function fromServerAttempt(attempt, questionIds) {
  if (!attempt) return null
  return {
    ...byPosition(questionIds, {
      answers: attempt.answers || {},
      flagged: attempt.flagged || [],
      currentQuestionId: attempt.current_question_id
    }),
    elapsedSeconds: Math.max(0, Number(attempt.elapsed_seconds) || 0),
    updatedAt: attempt.updated_at,
    attemptId: attempt.id,
    userId: null
  }
}

/**
 * The progress to send to the server for an attempt: answers and flags by question id.
 */
export function toServerProgress({ questionIds, answers, flagged, currentIndex, elapsedSeconds }) {
  const byId = {}
  for (const [i, option] of Object.entries(answers || {})) {
    const qid = questionIds[Number(i)]
    if (qid !== undefined && option !== undefined && option !== null) byId[qid] = option
  }
  return {
    answers: byId,
    flagged: [...(flagged || [])].map((i) => questionIds[i]).filter((qid) => qid !== undefined),
    currentQuestionId: questionIds[currentIndex] ?? null,
    elapsedSeconds: Math.max(0, Math.floor(elapsedSeconds || 0))
  }
}

/**
 * @param {number|string} examId
 * @param {{ questionIds: number[], answers: Record<number, number>, flagged: Set<number>|number[],
 *   currentIndex: number, elapsedSeconds: number, attemptId?: string|null, userId?: string|null }} state
 *   answers/flagged/currentIndex by position
 * @returns {string|null} the save time (ISO), or null if storage is unavailable
 */
export function saveAttempt(examId, state) {
  const updatedAt = new Date().toISOString()
  const ok = write(keyFor(examId), {
    v: VERSION,
    examId,
    ...toServerProgress(state),
    attemptId: state.attemptId || null,
    userId: state.userId || null,
    updatedAt
  })
  return ok ? updatedAt : null
}

export function clearAttempt(examId) {
  remove(keyFor(examId))
}
