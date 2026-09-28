<template>
  <div class="exam-preview-container">
    <!-- Error Boundary Wrapper -->
    <ErrorBoundary
      ref="errorBoundaryRef"
      :recoverable="true"
      @retry="handleRetry"
      @error-captured="handleErrorCaptured"
    >
      <!-- Loading State -->
      <ExamPreloader
        v-if="isLoading && !exam"
        :is-loading="true"
        loading-text="Loading exam..."
        :on-retry="handleRetry"
      />

      <!-- Error State -->
      <ExamPreloader
        v-else-if="error && !exam"
        :is-loading="false"
        :error="error"
        :on-retry="handleRetry"
      />

      <!-- Exam Content -->
      <div v-else-if="exam" class="exam-preview">
        <!-- Exam Header (Preview Mode) -->
        <ExamHeader v-if="!isQuizActive && !showResults" :exam="normalizedExam">
          <template #actions>
            <button
              class="btn btn-primary"
              @click="handleStartExam"
              :disabled="starting"
              aria-label="Start exam"
            >
              {{ starting ? '準備中…' : savedAttempt ? '繼續上次的作答' : '開始測驗' }}
            </button>
          </template>
        </ExamHeader>

        <!-- Quiz Message -->
        <div v-if="quizMessage" class="quiz-message" role="alert" aria-live="polite">
          {{ quizMessage }}
        </div>

        <!-- Testing Interface (Active Quiz) -->
        <section
          v-if="isQuizActive"
          class="testing-interface"
          role="main"
          aria-label="Exam testing interface"
          @keydown="handleKeyboardNavigation"
        >
          <div class="testing-header">
            <div class="testing-info">
              <strong>作答模式</strong>
              <span>第 {{ currentQuestionIndex + 1 }} / {{ totalQuestions }} 題</span>
              <span v-if="lastSavedAt && syncState === 'local'" class="save-status" aria-live="polite">
                <i class="bi bi-cloud-slash" aria-hidden="true"></i>
                進度先存在這台裝置，連上網路後會同步
              </span>
              <span v-else-if="lastSavedAt" class="save-status" aria-live="polite">
                <i class="bi bi-cloud-check" aria-hidden="true"></i>
                進度已自動儲存
              </span>
            </div>
            <TimerComponent
              v-if="timeLimitSeconds"
              :time-limit="timeLimitSeconds"
              :elapsed="elapsedSeconds"
              @time-warning="handleTimeWarning"
              @time-critical="handleTimeCritical"
              @time-expired="handleTimeExpired"
            />
          </div>

          <div class="testing-content">
            <div class="testing-sidebar">
              <QuestionNavigator
                :questions="normalizedQuestions"
                :current-index="currentQuestionIndex"
                :answered-questions="answeredQuestionsSet"
                :flagged-questions="flaggedQuestions"
                @navigate-to="navigateToQuestion"
              />
              <ProgressTracker
                :answered-questions="answeredQuestionsSet"
                :total-questions="totalQuestions"
              />
            </div>

            <div class="testing-main">
              <QuestionDisplay
                v-if="currentQuestion"
                :question="normalizedCurrentQuestion"
                :question-number="currentQuestionIndex + 1"
                :selected-answer="userAnswers[currentQuestionIndex]"
                @select-answer="selectAnswer"
              />

              <div class="quiz-actions" role="group" aria-label="Question navigation actions">
                <button
                  class="btn"
                  @click="prevQuestion"
                  :disabled="currentQuestionIndex === 0"
                  aria-label="Previous question"
                >
                  上一題
                </button>
                <button
                  class="btn"
                  :class="{ 'btn-flagged': isCurrentQuestionFlagged }"
                  @click="toggleFlag"
                  aria-label="Flag question for review"
                >
                  <i class="bi" :class="isCurrentQuestionFlagged ? 'bi-flag-fill' : 'bi-flag'"></i>
                  {{ isCurrentQuestionFlagged ? '取消標記' : '標記' }}
                </button>
                <button
                  class="btn"
                  @click="nextQuestion"
                  :disabled="currentQuestionIndex === totalQuestions - 1"
                  aria-label="Next question"
                >
                  下一題
                </button>
                <button
                  class="btn btn-secondary"
                  @click="handleSubmitExam"
                  aria-label="Submit exam"
                >
                  提交答案
                </button>
              </div>
            </div>
          </div>
        </section>

        <!-- Results Panel -->
        <section
          v-if="showResults && examResults"
          class="results-panel"
          role="main"
          aria-label="Exam results"
        >
          <ScoreDisplay
            :results="normalizedResults"
            :exam-name="exam.name"
            :show-metadata="true"
          />

          <ResultsBreakdown
            :results="normalizedResults"
            :show-explanations="showExplanations"
            :show-actions="true"
            @toggle-explanations="toggleExplanations"
            @review-incorrect="reviewIncorrectQuestions"
          />

          <ResultsActions
            :results="normalizedResults"
            :exam-name="exam.name"
            @retake-exam="handleRetakeExam"
            @return-to-list="goBack"
            @questions-bookmarked="handleQuestionsBookmarked"
            @flashcards-created="handleFlashcardsCreated"
          />
        </section>

        <!-- Question List (Preview Mode) -->
        <div v-if="!isQuizActive && !showResults" class="question-list">
          <article
            v-for="question in exam.exam_questions"
            :key="question.id"
            class="question-card"
            tabindex="0"
          >
            <header>
              <span class="order">第 {{ question.order }} 題</span>
              <span class="points" v-if="question.points">{{ question.points }} 分</span>
            </header>
            <p class="content">{{ question.question_content }}</p>
            <div class="question-meta">
              <span>{{ question.question_subject || '未分類' }}</span>
              <span>{{ question.question_category || '未分類' }}</span>
            </div>
          </article>
        </div>

        <!-- Footer Actions (Preview Mode) -->
        <footer v-if="!isQuizActive && !showResults" class="actions">
          <button class="btn" @click="goBack" aria-label="Go back">返回</button>
        </footer>
      </div>

      <!-- Empty State -->
      <div v-else class="empty-state" role="status" aria-live="polite">
        <p>{{ errorMessage || '載入考卷中...' }}</p>
      </div>
    </ErrorBoundary>

    <!-- Navigation Warning Modal -->
    <div
      v-if="showNavigationWarning"
      class="modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="warning-title"
    >
      <div class="modal-content">
        <h3 id="warning-title">離開測驗？</h3>
        <p>作答進度會保存，離開期間不計時。回到這份考卷時可以接著寫。</p>
        <div class="modal-actions">
          <button class="btn btn-secondary" @click="cancelNavigation">取消</button>
          <button class="btn btn-primary" @click="confirmNavigation">確定離開</button>
        </div>
      </div>
    </div>

    <!-- Resume Prompt: an unfinished attempt exists for this exam -->
    <div
      v-if="showResumePrompt && savedAttempt"
      class="modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="resume-title"
      aria-describedby="resume-desc"
    >
      <div class="modal-content resume-modal">
        <template v-if="!confirmingRestart">
          <h3 id="resume-title">{{ savedAttemptTimeUp ? '上次作答的時間已經用完' : '上次的作答還沒寫完' }}</h3>
          <p id="resume-desc">{{ savedAttemptWhen }} 離開，進度都有保存。</p>
          <dl class="resume-facts">
            <div>
              <dt>已作答</dt>
              <dd>{{ savedAttempt.answeredCount }} / {{ totalQuestions }} 題</dd>
            </div>
            <div>
              <dt>還剩時間</dt>
              <dd>{{ savedAttemptTimeLeft }}</dd>
            </div>
            <div>
              <dt>標記待複查</dt>
              <dd>{{ savedAttempt.flagged.size }} 題</dd>
            </div>
            <div>
              <dt>停在</dt>
              <dd>第 {{ savedAttempt.currentIndex + 1 }} 題</dd>
            </div>
          </dl>
          <p class="resume-note">離開期間不計時。換一台裝置登入，也能接著寫。</p>
          <div class="resume-actions">
            <button v-if="savedAttemptTimeUp" class="btn btn-primary" @click="submitSavedAttempt">
              交卷，看這次的成績
            </button>
            <button v-else class="btn btn-primary" @click="resumeAttempt">
              繼續作答，從第 {{ savedAttempt.currentIndex + 1 }} 題開始
            </button>
            <button class="btn btn-secondary" @click="confirmingRestart = true">重新開始</button>
            <button class="btn btn-link" @click="showResumePrompt = false">先不要</button>
          </div>
        </template>
        <template v-else>
          <h3 id="resume-title">清除進度並重新開始？</h3>
          <p id="resume-desc">
            已作答的 {{ savedAttempt.answeredCount }} 題和 {{ savedAttempt.flagged.size }} 個標記都會清除<template v-if="timeLimitSeconds">，時間從 {{ exam.time_limit }} 分鐘重新計算</template>。
          </p>
          <p v-if="restartError" class="resume-error" role="alert">{{ restartError }}</p>
          <div class="modal-actions">
            <button class="btn btn-secondary" @click="confirmingRestart = false; restartError = ''">返回</button>
            <button class="btn btn-danger" @click="restartAttempt">清除並重新開始</button>
          </div>
        </template>
      </div>
    </div>

    <!-- Another tab or device continued this attempt: stop here rather than overwrite it -->
    <div
      v-if="takenOver"
      class="modal-overlay"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby="taken-over-title"
      aria-describedby="taken-over-desc"
    >
      <div class="modal-content resume-modal">
        <h3 id="taken-over-title">這次作答在別的地方接著寫了</h3>
        <p id="taken-over-desc">
          另一個分頁或裝置繼續了這次作答，這裡的進度可能比較舊。為了不蓋掉那邊的答案，這裡先停下來，也暫停計時。
        </p>
        <div class="resume-actions">
          <button class="btn btn-primary" @click="loadLatestAttempt">載入最新的進度</button>
          <button class="btn btn-secondary" @click="keepThisAttempt">改用這裡的進度繼續</button>
        </div>
      </div>
    </div>

    <!-- Submission Error Modal -->
    <div
      v-if="showSubmissionError"
      class="modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="submission-error-title"
    >
      <div class="modal-content error-modal">
        <h3 id="submission-error-title">提交失敗</h3>
        <p>{{ submissionErrorMessage }}</p>
        <p class="error-hint">成績還在這個頁面上，可以重新提交；離開頁面前請先提交成功。</p>
        <div class="modal-actions">
          <button class="btn btn-secondary" @click="dismissSubmissionError">稍後再試</button>
          <button class="btn btn-primary" @click="retrySubmission">重新提交</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router'
import { useExamStore } from '@/stores/examStore'
import questionService from '@/services/questionService'
import examService from '@/services/examService'
import { useExamClock } from '@/composables/useExamClock'
import { loadAttempt, saveAttempt, clearAttempt, fromServerAttempt, toServerProgress } from '@/lib/examAttemptStorage'
import { formatWhen, formatSecondsLeft } from '@/lib/attemptFormat'

// Import components
import ExamHeader from '@/components/exam/ExamHeader.vue'
import ExamPreloader from '@/components/exam/ExamPreloader.vue'
import TimerComponent from '@/components/exam/TimerComponent.vue'
import QuestionNavigator from '@/components/exam/QuestionNavigator.vue'
import ProgressTracker from '@/components/exam/ProgressTracker.vue'
import QuestionDisplay from '@/components/exam/QuestionDisplay.vue'
import ScoreDisplay from '@/components/exam/ScoreDisplay.vue'
import ResultsBreakdown from '@/components/exam/ResultsBreakdown.vue'
import ResultsActions from '@/components/exam/ResultsActions.vue'
import ErrorBoundary from '@/components/exam/ErrorBoundary.vue'

const route = useRoute()
const router = useRouter()
const examStore = useExamStore()

// Local state
const exam = ref(null)
const errorMessage = ref('')
const error = ref(null)
const starting = ref(false)
const isQuizActive = ref(false)
const currentQuestionIndex = ref(0)
const quizMessage = ref('')
const userAnswers = ref({})
const questionDetails = ref({})
const showResults = ref(false)
const examResults = ref(null)
const isLoading = ref(false)
const showExplanations = ref(false)
const showNavigationWarning = ref(false)
const errorBoundaryRef = ref(null)
const showSubmissionError = ref(false)
const submissionErrorMessage = ref('')
const flaggedQuestions = ref(new Set())

// Unfinished attempt saved for this exam (see examAttemptStorage), and the resume prompt
const savedAttempt = ref(null)
const showResumePrompt = ref(false)
const confirmingRestart = ref(false)
const lastSavedAt = ref(null)

// Server-side attempt (exam_attempt). null while offline: progress then stays on this device.
const attemptId = ref(null)
const submittedAttemptId = ref(null)
const currentUserId = ref(null)
const syncState = ref(null) // 'synced' | 'local'
let serverSaveTimer = null

// This page, as a writer of the attempt. Continuing an attempt from the resume prompt
// claims it; once another tab or device claims it, this page's saves are refused.
const writerId = crypto.randomUUID()
let claimOnNextSave = false
const takenOver = ref(false)

// Time actually spent answering; pauses while the page is hidden or left
const { elapsedSeconds, start: startClock, pause: pauseClock, sync: syncClock } = useExamClock()

// Computed properties
const totalQuestions = computed(() => exam.value?.exam_questions?.length || 0)

const questionIds = computed(() => (exam.value?.exam_questions || []).map((eq) => eq.question))

// The limit the server attempt started with (null: none), so editing the exam doesn't
// change the time of a sitting already under way. undefined: no server attempt.
const attemptTimeLimitSeconds = ref(undefined)

// null when there is no time limit
const timeLimitSeconds = computed(() => {
  const snapshot = savedAttempt.value ? savedAttempt.value.timeLimitSeconds : attemptTimeLimitSeconds.value
  if (snapshot !== undefined) return snapshot
  const minutes = Number(exam.value?.time_limit)
  return Number.isFinite(minutes) && minutes > 0 ? minutes * 60 : null
})

const savedAttemptTimeUp = computed(() =>
  !!(savedAttempt.value && timeLimitSeconds.value && savedAttempt.value.elapsedSeconds >= timeLimitSeconds.value)
)

const savedAttemptTimeLeft = computed(() => {
  if (!savedAttempt.value) return ''
  if (!timeLimitSeconds.value) return '不限時'
  return formatSecondsLeft(Math.max(0, timeLimitSeconds.value - savedAttempt.value.elapsedSeconds))
})

const savedAttemptWhen = computed(() => formatWhen(savedAttempt.value?.updatedAt))

const currentQuestion = computed(() => {
  if (!exam.value) return null
  return exam.value.exam_questions[currentQuestionIndex.value] || null
})

const currentQuestionOptions = computed(() => {
  if (!currentQuestion.value) return []
  const qId = currentQuestion.value.question
  return questionDetails.value[qId]?.options || []
})

const answeredQuestionsSet = computed(() => {
  return new Set(Object.keys(userAnswers.value).map(Number))
})

const isCurrentQuestionFlagged = computed(() => {
  return flaggedQuestions.value.has(currentQuestionIndex.value)
})

// Normalize exam data for ExamHeader component
const normalizedExam = computed(() => {
  if (!exam.value) return null
  return {
    name: exam.value.name,
    description: exam.value.description,
    timeLimit: exam.value.time_limit,
    questions: exam.value.exam_questions || []
  }
})

// Normalize questions for QuestionNavigator
const normalizedQuestions = computed(() => {
  if (!exam.value?.exam_questions) return []
  return exam.value.exam_questions.map((eq, index) => ({
    id: eq.id || eq.question,
    order: eq.order || index + 1,
    content: eq.question_content,
    subject: eq.question_subject,
    category: eq.question_category
  }))
})

// Normalize current question for QuestionDisplay
const normalizedCurrentQuestion = computed(() => {
  if (!currentQuestion.value) return null
  const qId = currentQuestion.value.question
  const details = questionDetails.value[qId]
  
  return {
    id: currentQuestion.value.id || qId,
    order: currentQuestion.value.order,
    content: currentQuestion.value.question_content,
    options: details?.options?.map(opt => ({
      id: opt.id,
      content: opt.content,
      isCorrect: opt.is_correct
    })) || [],
    subject: currentQuestion.value.question_subject,
    category: currentQuestion.value.question_category
  }
})

// Normalize results for ScoreDisplay, ResultsBreakdown and ResultsActions
const normalizedResults = computed(() => {
  if (!examResults.value) return null
  return {
    examId: exam.value?.id?.toString() || '',
    score: examResults.value.score,
    correctCount: examResults.value.correct,
    totalCount: examResults.value.total,
    percentage: Math.round((examResults.value.correct / examResults.value.total) * 100),
    duration: examResults.value.duration || 0,
    details: examResults.value.details || [],
    wrongQuestionIds: examResults.value.wrongQuestionIds || []
  }
})

// Methods
const loadExam = async () => {
  isLoading.value = true
  error.value = null
  errorMessage.value = ''
  
  try {
    const { data } = await examStore.getExam(route.params.id)
    exam.value = data
    await loadAllQuestionDetails()
    
    // An unfinished attempt? Ask whether to continue instead of resuming silently.
    savedAttempt.value = await loadSavedAttempt()
    showResumePrompt.value = !!savedAttempt.value
  } catch (err) {
    const friendlyError = createUserFriendlyError(err)
    error.value = friendlyError.message
    errorMessage.value = friendlyError.message
  } finally {
    isLoading.value = false
  }
}

// The unfinished attempt to offer: the server's, merged with this device's copy.
const loadSavedAttempt = async () => {
  const examId = exam.value.id
  try {
    currentUserId.value = await examService.getCurrentUserId()
  } catch {
    currentUserId.value = null
  }

  let local = loadAttempt(examId, questionIds.value)
  // Progress left on this browser by a different account (or with no one signed in) is not this user's
  if (local?.userId && local.userId !== currentUserId.value) local = null

  let server = null
  let serverReachable = true
  try {
    server = fromServerAttempt((await examService.getExamAttempt(examId)).data, questionIds.value)
  } catch (err) {
    serverReachable = false
    console.warn('Could not load the saved attempt from the server; using this device only', err)
  }

  if (server) {
    // Answers made on this device that never reached the server (e.g. offline) win when
    // newer, but time used only moves forward. That includes a sitting started offline,
    // before this device had a server attempt: it carries on as the server's attempt.
    const unsynced = local && (local.attemptId === server.attemptId || !local.attemptId)
    if (unsynced && new Date(local.updatedAt) > new Date(server.updatedAt)) {
      return {
        ...local,
        attemptId: server.attemptId,
        elapsedSeconds: Math.max(local.elapsedSeconds, server.elapsedSeconds),
        timeLimitSeconds: server.timeLimitSeconds
      }
    }
    return server
  }
  // No open attempt on the server, but this copy belonged to one: it was submitted
  // or abandoned elsewhere, so it is stale.
  if (local?.attemptId && serverReachable) {
    clearAttempt(examId)
    return null
  }
  return local
}

// Start (or get the already open) attempt on the server. Failing leaves progress on this device.
const openServerAttempt = async () => {
  try {
    const { data } = await examService.startExamAttempt(exam.value.id)
    attemptId.value = data?.id || null
    attemptTimeLimitSeconds.value = data?.id ? (data.time_limit_seconds ?? null) : undefined
  } catch (err) {
    attemptId.value = null
    attemptTimeLimitSeconds.value = undefined
    console.warn('Could not start the attempt on the server; progress stays on this device', err)
  }
  syncState.value = attemptId.value ? 'synced' : 'local'
}

const loadAllQuestionDetails = async () => {
  if (!exam.value) return
  
  const loadPromises = exam.value.exam_questions.map(async (eq) => {
    if (!eq.question) return
    try {
      const { data } = await questionService.getQuestion(eq.question)
      questionDetails.value[eq.question] = data
    } catch (err) {
      console.error(`Failed to load question ${eq.question}`, err)
    }
  })
  
  await Promise.all(loadPromises)
}

const handleStartExam = async () => {
  if (!exam.value || starting.value) return

  // Never start over on top of saved progress without asking
  if (savedAttempt.value) {
    confirmingRestart.value = false
    showResumePrompt.value = true
    return
  }

  starting.value = true
  quizMessage.value = ''
  userAnswers.value = {}
  showResults.value = false
  
  try {
    await examStore.startExam(exam.value.id)
    await openServerAttempt()
    launchQuiz()
  } catch (err) {
    const friendlyError = createUserFriendlyError(err)
    errorMessage.value = friendlyError.message
    quizMessage.value = friendlyError.message
  } finally {
    starting.value = false
  }
}

const launchQuiz = () => {
  isQuizActive.value = true
  currentQuestionIndex.value = 0
  flaggedQuestions.value = new Set()
  startClock(0)
  persistExamState()
}

// Restore the saved attempt's answers, position, attempt id and time used
const applySavedAttempt = () => {
  const saved = savedAttempt.value
  userAnswers.value = { ...saved.answers }
  flaggedQuestions.value = new Set(saved.flagged)
  currentQuestionIndex.value = saved.currentIndex
  attemptId.value = saved.attemptId
  attemptTimeLimitSeconds.value = saved.timeLimitSeconds
  startClock(saved.elapsedSeconds)
  savedAttempt.value = null
  showResumePrompt.value = false
  return saved
}

const resumeAttempt = async () => {
  const saved = applySavedAttempt()
  showResults.value = false
  isQuizActive.value = true
  quizMessage.value = `已接著上次的進度，從第 ${saved.currentIndex + 1} 題開始`
  syncState.value = saved.attemptId ? 'synced' : 'local'
  claimOnNextSave = true // continuing here takes the attempt over from any other tab or device
  persistExamState()
  // Progress that only existed on this device gets an attempt on the server now
  if (!attemptId.value) await openServerAttempt()
  await flushServerSave()
}

// The saved attempt has no time left: grade what was answered.
const submitSavedAttempt = () => {
  applySavedAttempt()
  submitExam(true)
}

const restartError = ref('')

const restartAttempt = async () => {
  const previousAttemptId = savedAttempt.value?.attemptId
  restartError.value = ''
  // The server must close the old attempt first; otherwise starting again would
  // hand back that same attempt with its time already used.
  if (previousAttemptId) {
    try {
      await examService.abandonExamAttempt(previousAttemptId)
    } catch (err) {
      console.warn('Could not abandon the previous attempt on the server', err)
      restartError.value = '現在連不上伺服器，進度沒有清除。請確認網路後再試一次。'
      return
    }
  }
  clearAttempt(exam.value.id)
  savedAttempt.value = null
  showResumePrompt.value = false
  confirmingRestart.value = false
  userAnswers.value = {}
  await handleStartExam()
}

const selectAnswer = (optionId) => {
  if (!isQuizActive.value) return
  userAnswers.value[currentQuestionIndex.value] = optionId
  persistExamState()
}

const navigateToQuestion = (index) => {
  if (index >= 0 && index < totalQuestions.value) {
    currentQuestionIndex.value = index
    persistExamState()
  }
}

const nextQuestion = () => {
  if (!exam.value) return
  currentQuestionIndex.value = Math.min(
    currentQuestionIndex.value + 1,
    totalQuestions.value - 1
  )
  persistExamState()
}

const prevQuestion = () => {
  currentQuestionIndex.value = Math.max(currentQuestionIndex.value - 1, 0)
  persistExamState()
}

const toggleFlag = () => {
  const index = currentQuestionIndex.value
  const newFlagged = new Set(flaggedQuestions.value)
  if (newFlagged.has(index)) {
    newFlagged.delete(index)
  } else {
    newFlagged.add(index)
  }
  flaggedQuestions.value = newFlagged
  persistExamState()
}

const handleSubmitExam = async () => {
  if (!confirm('確定要提交答案嗎？')) return
  await submitExam(false)
}

const submitExam = async (autoSubmit = false) => {
  pauseClock()
  isQuizActive.value = false
  // Graded from here on: no longer an unfinished attempt, even if saving the result fails.
  // The server closes it together with saving the result (save_exam_result + attempt id).
  clearTimeout(serverSaveTimer)
  submittedAttemptId.value = attemptId.value
  attemptId.value = null
  if (exam.value) clearAttempt(exam.value.id)
  lastSavedAt.value = null

  let correct = 0
  const total = totalQuestions.value
  const results = []
  const wrongQuestionIds = []
  
  exam.value.exam_questions.forEach((eq, index) => {
    const qId = eq.question
    const questionData = questionDetails.value[qId]
    
    if (!questionData) {
      results.push({
        questionId: qId,
        question: eq.question_content,
        isCorrect: false,
        userAnswer: null,
        correctAnswer: null
      })
      wrongQuestionIds.push(qId)
      return
    }
    
    const userAnswerId = userAnswers.value[index]
    const correctOption = questionData.options.find(opt => opt.is_correct)
    const userOption = questionData.options.find(opt => opt.id === userAnswerId)
    
    const isCorrect = correctOption && userAnswerId === correctOption.id
    if (isCorrect) {
      correct++
    } else {
      wrongQuestionIds.push(qId)
    }
    
    results.push({
      questionId: qId,
      question: eq.question_content,
      isCorrect,
      userAnswer: userOption?.content || '未作答',
      correctAnswer: correctOption?.content || '無正確答案'
    })
  })
  
  const score = Math.round((correct / total) * 100)
  // Time actually spent answering (pauses while away are excluded)
  const durationSeconds = elapsedSeconds.value
  
  examResults.value = {
    correct,
    total,
    score,
    details: results,
    wrongQuestionIds,
    duration: durationSeconds
  }
  
  // Show results immediately (don't wait for backend)
  showResults.value = true
  quizMessage.value = autoSubmit ? '時間到！測驗已自動提交' : '測驗已提交'
  
  // Save results to backend in background (non-blocking)
  saveResultsToBackend()
}

// An attempt started offline has no server attempt yet: open one before saving the
// result, so a retry after a lost response returns the first result instead of adding
// another. Still unreachable: the result is saved without one.
const ensureSubmittedAttempt = async () => {
  if (submittedAttemptId.value) return
  try {
    const { data } = await examService.startExamAttempt(exam.value.id)
    submittedAttemptId.value = data?.id || null
  } catch (err) {
    console.warn('Could not open a server attempt for the result', err)
  }
}

// Save the graded examResults. On failure the results stay on screen and the
// submission error modal offers a retry. Returns whether the save succeeded.
const saveResultsToBackend = async () => {
  const results = examResults.value
  if (!results) return false
  try {
    await ensureSubmittedAttempt()
    await examStore.saveExamResult({
      exam_id: exam.value.id,
      score: results.score,
      correct_count: results.correct,
      total_count: results.total,
      duration_seconds: results.duration,
      wrong_question_ids: results.wrongQuestionIds,
      // Same attempt on every retry: a retry after a lost response doesn't create a second result
      attempt_id: submittedAttemptId.value
    })
    return true
  } catch (err) {
    console.error('Failed to save exam result:', err)
    submissionErrorMessage.value = createUserFriendlyError(err).message
    showSubmissionError.value = true
    return false
  }
}

const retrySubmission = async () => {
  showSubmissionError.value = false
  if (await saveResultsToBackend()) quizMessage.value = '成績已成功保存'
}

const dismissSubmissionError = () => {
  showSubmissionError.value = false
}

// Timer event handlers
const handleTimeWarning = (timeLeft) => {
  console.log('Time warning:', timeLeft, 'seconds remaining')
}

const handleTimeCritical = (timeLeft) => {
  console.log('Time critical:', timeLeft, 'seconds remaining')
}

const handleTimeExpired = () => {
  submitExam(true)
}

// Results actions handlers
const handleRetakeExam = () => {
  showResults.value = false
  examResults.value = null
  userAnswers.value = {}
  quizMessage.value = ''
  handleStartExam()
}

const goBack = () => {
  router.back()
}

const handleQuestionsBookmarked = ({ questionIds, count }) => {
  console.log(`Bookmarked ${count} questions:`, questionIds)
}

const handleFlashcardsCreated = ({ flashcards, count }) => {
  console.log(`Created ${count} flashcards:`, flashcards)
}

const toggleExplanations = () => {
  showExplanations.value = !showExplanations.value
}

const reviewIncorrectQuestions = () => {
  // Navigate to first incorrect question in results
  const firstIncorrect = examResults.value?.details?.findIndex(d => !d.isCorrect)
  if (firstIncorrect !== undefined && firstIncorrect >= 0) {
    // Scroll to that question in the breakdown
    const element = document.querySelector(`[data-question-index="${firstIncorrect}"]`)
    element?.scrollIntoView({ behavior: 'smooth' })
  }
}

// Keyboard navigation
const handleKeyboardNavigation = (event) => {
  if (!isQuizActive.value) return
  
  switch (event.key) {
    case 'ArrowLeft':
      if (!event.target.closest('button')) {
        prevQuestion()
      }
      break
    case 'ArrowRight':
      if (!event.target.closest('button')) {
        nextQuestion()
      }
      break
    case '1':
    case '2':
    case '3':
    case '4':
    case '5': {
      const option = currentQuestionOptions.value[Number(event.key) - 1]
      if (option) selectAnswer(option.id)
      break
    }
  }
}

// State persistence: the unfinished attempt is saved on this device at once
// (see examAttemptStorage) and sent to the server shortly after.
const currentProgress = () => ({
  questionIds: questionIds.value,
  answers: userAnswers.value,
  flagged: flaggedQuestions.value,
  currentIndex: currentQuestionIndex.value,
  elapsedSeconds: elapsedSeconds.value
})

const persistExamState = () => {
  if (!exam.value || !isQuizActive.value || takenOver.value) return
  syncClock()
  const savedAt = saveAttempt(exam.value.id, {
    ...currentProgress(),
    attemptId: attemptId.value,
    userId: currentUserId.value,
    writerId,
    timeLimitSeconds: attemptTimeLimitSeconds.value
  })
  if (savedAt) lastSavedAt.value = savedAt
  scheduleServerSave()
}

const scheduleServerSave = () => {
  clearTimeout(serverSaveTimer)
  serverSaveTimer = setTimeout(() => flushServerSave(), 2000)
}

// Send the progress to the server now. `keepalive` is for the page being hidden or closed.
const flushServerSave = async ({ keepalive = false } = {}) => {
  clearTimeout(serverSaveTimer)
  serverSaveTimer = null
  if (!exam.value || !isQuizActive.value || takenOver.value) return
  if (!attemptId.value) {
    if (keepalive) return
    await openServerAttempt() // e.g. it failed while offline; try again
    if (!attemptId.value) return
  }
  const progress = toServerProgress(currentProgress())
  const claim = claimOnNextSave
  try {
    await examService.saveAttemptProgress(attemptId.value, progress, { writerId, claim, keepalive })
    if (claim) claimOnNextSave = false
    syncState.value = 'synced'
  } catch (err) {
    if (err.conflict) {
      stopForTakeover()
      return
    }
    syncState.value = 'local'
    console.warn('Could not save progress to the server; it is kept on this device', err)
  }
}

// Another tab or device continued the attempt. Stop answering and counting time here
// until the user picks which progress to keep.
const stopForTakeover = () => {
  if (takenOver.value) return
  clearTimeout(serverSaveTimer)
  pauseClock()
  takenOver.value = true
}

// Discard this page's (older) progress and offer the attempt as saved elsewhere.
const loadLatestAttempt = async () => {
  isQuizActive.value = false
  takenOver.value = false
  // This page's own copy on this device would otherwise look newer than the server's
  if (loadAttempt(exam.value.id, questionIds.value)?.writerId === writerId) clearAttempt(exam.value.id)
  savedAttempt.value = await loadSavedAttempt()
  showResumePrompt.value = !!savedAttempt.value
}

// Keep going with this page's progress: take the attempt back, overwriting the other.
const keepThisAttempt = async () => {
  takenOver.value = false
  claimOnNextSave = true
  startClock(elapsedSeconds.value)
  persistExamState()
  await flushServerSave()
}

// Save the time used every 10 seconds, and whenever the page is hidden or closed
watch(elapsedSeconds, (seconds) => {
  if (isQuizActive.value && seconds > 0 && seconds % 10 === 0) persistExamState()
})

const saveBeforeLeaving = () => {
  persistExamState()
  flushServerSave({ keepalive: true })
}

const persistOnHide = () => {
  if (document.visibilityState === 'hidden') saveBeforeLeaving()
}

// Save and stop the clock when leaving within the app; the attempt stays unfinished
// and can be resumed. flushServerSave reads the progress before its first await.
const suspendAttempt = () => {
  persistExamState()
  flushServerSave()
  pauseClock()
}

// Error handling
const createUserFriendlyError = (err) => {
  let message = '發生未預期的錯誤，請稍後再試。'
  let recoverable = true
  
  if (err.name === 'NetworkError' || !navigator.onLine) {
    message = '無法連接到伺服器，請檢查您的網路連線後再試。'
    recoverable = true
  } else if (err.response?.status === 404) {
    message = '找不到此考卷，請確認考卷編號是否正確。'
    recoverable = false
  } else if (err.response?.status === 403) {
    message = '您沒有權限存取此考卷，請聯繫管理員。'
    recoverable = false
  } else if (err.response?.status >= 500) {
    message = '伺服器目前發生問題，請稍後再試。'
    recoverable = true
  }
  
  return { message, recoverable }
}

const handleRetry = () => {
  // Reset error boundary if it exists
  if (errorBoundaryRef.value) {
    errorBoundaryRef.value.reset()
  }
  loadExam()
}

const handleErrorCaptured = ({ error, errorInfo }) => {
  console.error('Error captured by boundary:', error, errorInfo)
}

// Navigation guard
const pendingNavigationTo = ref(null)

const cancelNavigation = () => {
  showNavigationWarning.value = false
  pendingNavigationTo.value = null
}

const confirmNavigation = () => {
  showNavigationWarning.value = false
  // Save the destination before clearing
  const destination = pendingNavigationTo.value
  pendingNavigationTo.value = null
  
  // Navigate to the saved destination
  if (destination) {
    suspendAttempt()
    isQuizActive.value = false
    router.push(destination)
  }
}

// Route leave guard
onBeforeRouteLeave((to, from, next) => {
  if (isQuizActive.value && !pendingNavigationTo.value) {
    showNavigationWarning.value = true
    pendingNavigationTo.value = to.fullPath
    next(false)
  } else {
    next()
  }
})

// Lifecycle hooks
onMounted(() => {
  loadExam()

  // Handle browser refresh/close warning, and save progress whenever the page goes away
  window.addEventListener('beforeunload', handleBeforeUnload)
  window.addEventListener('pagehide', saveBeforeLeaving)
  document.addEventListener('visibilitychange', persistOnHide)
})

onBeforeUnmount(() => {
  suspendAttempt()
  window.removeEventListener('beforeunload', handleBeforeUnload)
  window.removeEventListener('pagehide', saveBeforeLeaving)
  document.removeEventListener('visibilitychange', persistOnHide)
})

const handleBeforeUnload = (event) => {
  if (isQuizActive.value) {
    persistExamState()
    event.preventDefault()
    event.returnValue = ''
  }
}

// Expose for testing
defineExpose({
  exam,
  isQuizActive,
  userAnswers,
  examResults,
  loadExam,
  submitExam,
  examStore
})
</script>

<style scoped>
.exam-preview-container {
  min-height: 100vh;
  background: var(--bg-page);
}

.exam-preview {
  max-width: 1200px;
  margin: 0 auto;
  padding: 24px;
}

.quiz-message {
  margin: 16px 0;
  background: var(--warning-soft);
  color: var(--warning);
  padding: 12px 16px;
  border-radius: 8px;
  font-weight: 500;
}

/* Testing Interface */
.testing-interface {
  background: var(--surface);
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  overflow: hidden;
}

.testing-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px 24px;
  background: var(--bg-page);
  border-bottom: 1px solid var(--border);
}

.testing-info {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.testing-info strong {
  color: var(--text-primary);
  font-size: 16px;
}

.testing-info span {
  color: var(--text-secondary);
  font-size: 14px;
}

.testing-content {
  display: grid;
  grid-template-columns: 280px 1fr;
  min-height: 500px;
}

.testing-sidebar {
  padding: 16px;
  background: var(--bg-page);
  border-right: 1px solid var(--border);
}

.testing-main {
  padding: 24px;
  display: flex;
  flex-direction: column;
}

.quiz-actions {
  display: flex;
  gap: 12px;
  justify-content: flex-end;
  margin-top: auto;
  padding-top: 24px;
  border-top: 1px solid var(--border);
}

/* Results Panel */
.results-panel {
  display: flex;
  flex-direction: column;
  gap: 24px;
}

/* Question List (Preview Mode) */
.question-list {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.question-card {
  background: var(--surface);
  padding: 20px;
  border-radius: 8px;
  box-shadow: 0 1px 4px rgba(0,0,0,0.05);
  transition: box-shadow 0.2s;
}

.question-card:hover {
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.question-card:focus {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}

.question-card header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 8px;
  color: var(--text-secondary);
}

.question-card .order {
  font-weight: 600;
}

.question-card .points {
  color: var(--primary-text);
  font-weight: 500;
}

.question-card .content {
  color: var(--text-primary);
  line-height: 1.6;
  margin: 0 0 12px 0;
}

.question-meta {
  display: flex;
  gap: 12px;
  color: var(--text-muted);
  font-size: 13px;
}

/* Footer Actions */
.actions {
  margin-top: 32px;
  display: flex;
  gap: 12px;
  justify-content: flex-end;
}

/* Buttons */
.btn {
  padding: 10px 18px;
  border-radius: 6px;
  border: none;
  cursor: pointer;
  font-weight: 500;
  transition: all 0.2s;
  font-size: 14px;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn:focus {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}

.btn-primary {
  background: var(--primary);
  color: var(--on-primary);
}

.btn-primary:hover:not(:disabled) {
  background: var(--primary-hover);
}

.btn-secondary {
  background: #6b7280;
  color: white;
}

.btn-secondary:hover:not(:disabled) {
  background: #4b5563;
}

.btn-flagged {
  background: var(--warning-soft);
  color: #ea580c;
  border: 1px solid #f97316;
}

.btn-flagged:hover:not(:disabled) {
  background: var(--warning-soft);
}

.btn i {
  margin-right: 4px;
}

/* Empty State */
.empty-state {
  text-align: center;
  padding: 60px;
  color: var(--text-secondary);
}

/* Modal */
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.modal-content {
  background: var(--surface);
  padding: 24px;
  border-radius: 12px;
  max-width: 400px;
  width: 90%;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
}

.modal-content h3 {
  margin: 0 0 12px 0;
  color: var(--text-primary);
}

.modal-content p {
  color: var(--text-secondary);
  margin: 0 0 20px 0;
  line-height: 1.5;
}

.modal-actions {
  display: flex;
  gap: 12px;
  justify-content: flex-end;
}

.btn-danger {
  background: var(--danger);
  color: var(--on-primary);
}

.btn-link {
  background: transparent;
  color: var(--text-secondary);
}

.btn-link:hover:not(:disabled) {
  color: var(--text-primary);
}

.save-status {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 13px;
  color: var(--text-muted);
}

/* Resume Prompt */
.modal-content.resume-modal {
  max-width: 480px;
  padding: 28px;
  background: var(--surface-raised);
  border: 1px solid var(--border);
}

.resume-modal h3 {
  font-size: 21px;
}

.resume-facts {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 1px;
  margin: 16px 0 12px;
  background: var(--border);
  border: 1px solid var(--border);
  border-radius: 12px;
  overflow: hidden;
  font-variant-numeric: tabular-nums;
}

.resume-facts div {
  padding: 12px 14px;
  background: var(--surface-raised);
}

.resume-facts dt {
  font-size: 13px;
  font-weight: 400;
  color: var(--text-secondary);
}

.resume-facts dd {
  margin: 4px 0 0;
  font-size: 19px;
  font-weight: 700;
  color: var(--text-primary);
}

.modal-content p.resume-note {
  font-size: 14px;
  color: var(--text-muted);
}

.modal-content p.resume-error {
  padding: 8px 12px;
  border-radius: 8px;
  background: var(--danger-soft);
  color: var(--danger);
  font-size: 14px;
}

.resume-actions {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.resume-actions .btn {
  width: 100%;
  min-height: 44px;
  justify-content: center;
}

/* Error Modal */
.error-modal h3 {
  color: var(--danger);
}

.error-hint {
  font-size: 14px;
  color: var(--success);
  background: var(--success-soft);
  padding: 8px 12px;
  border-radius: 6px;
  margin-bottom: 16px;
}

/* Responsive Design */
@media (max-width: 1024px) {
  .testing-content {
    grid-template-columns: 1fr;
  }
  
  .testing-sidebar {
    border-right: none;
    border-bottom: 1px solid var(--border);
    display: flex;
    gap: 16px;
    flex-wrap: wrap;
  }
  
  .testing-sidebar > * {
    flex: 1;
    min-width: 200px;
  }
}

@media (max-width: 768px) {
  .exam-preview {
    padding: 16px;
  }
  
  .testing-header {
    flex-direction: column;
    gap: 12px;
    align-items: flex-start;
    padding: 12px 16px;
  }
  
  .testing-main {
    padding: 16px;
  }
  
  .quiz-actions {
    flex-wrap: wrap;
  }
  
  .quiz-actions .btn {
    flex: 1;
    min-width: 100px;
  }
  
  .question-card {
    padding: 16px;
  }
}

@media (max-width: 480px) {
  .exam-preview {
    padding: 12px;
  }
  
  .testing-sidebar {
    flex-direction: column;
  }
  
  .testing-sidebar > * {
    min-width: 100%;
  }
  
  .quiz-actions {
    flex-direction: column;
  }
  
  .quiz-actions .btn {
    width: 100%;
  }
  
  .modal-content {
    padding: 20px;
  }
  
  .modal-actions {
    flex-direction: column;
  }
  
  .modal-actions .btn {
    width: 100%;
  }
}

/* High Contrast Mode */
@media (prefers-contrast: high) {
  .testing-interface {
    border: 2px solid #1f2937;
  }
  
  .question-card {
    border: 2px solid #1f2937;
  }
  
  .quiz-message {
    border: 2px solid #92400e;
  }
}

/* Reduced Motion */
@media (prefers-reduced-motion: reduce) {
  .btn,
  .question-card {
    transition: none;
  }
}

/* Focus Visible */
.btn:focus-visible,
.question-card:focus-visible {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}
</style>
