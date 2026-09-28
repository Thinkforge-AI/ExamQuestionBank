<template>
    <div class="my-exams">
        <div class="page-head">
            <div class="page-title-group">
                <h1 class="page-title">我的考卷</h1>
                <span v-if="!loading && exams.length" class="page-count">共 {{ exams.length }} 份</span>
            </div>
            <div class="page-actions">
                <button type="button" class="action action-outline" @click="openMockExamModal">
                    <i class="bi bi-shuffle" aria-hidden="true"></i>隨機模擬考
                </button>
                <button type="button" class="action" :class="openAttemptExam ? 'action-outline' : 'action-primary'"
                    @click="router.push('/exams/create')">
                    <i class="bi bi-plus-lg" aria-hidden="true"></i>建立考卷
                </button>
            </div>
        </div>

        <div v-if="loading" class="state-panel" role="status">
            <div class="spinner" aria-hidden="true"></div>
            <p>載入考卷中…</p>
        </div>

        <div v-else-if="loadError" class="state-panel" role="alert">
            <p>{{ loadError }}</p>
            <button type="button" class="action action-outline" @click="loadExams">重新載入</button>
        </div>

        <!-- Empty state -->
        <section v-else-if="!exams.length" class="empty-panel" aria-labelledby="empty-title">
            <svg class="empty-art" width="200" height="160" viewBox="0 0 200 160" fill="none" aria-hidden="true">
                <rect x="46" y="26" width="104" height="128" rx="8" class="art-back"></rect>
                <rect x="30" y="14" width="104" height="128" rx="8" class="art-front"></rect>
                <path d="M50 42h64M50 60h64M50 78h42" class="art-lines"></path>
                <circle cx="146" cy="116" r="26" class="art-badge"></circle>
                <path d="M146 104v24M134 116h24" class="art-plus"></path>
            </svg>
            <div class="empty-copy">
                <h2 id="empty-title">還沒有考卷</h2>
                <p>從題庫挑題組成自己的考卷，可以限時作答、列印，作答後會記下成績。想先試試手感，也可以從歷屆考卷隨機抽題做一次模擬考。</p>
                <div class="empty-actions">
                    <button type="button" class="action action-primary" @click="router.push('/exams/create')">
                        <i class="bi bi-plus-lg" aria-hidden="true"></i>建立第一份考卷
                    </button>
                    <button type="button" class="action action-outline" @click="openMockExamModal">隨機模擬考</button>
                </div>
            </div>
        </section>

        <template v-else>
            <!-- Unfinished attempt first; otherwise the last exam practised -->
            <section v-if="openAttemptExam" class="spotlight spotlight-open" aria-labelledby="spotlight-title">
                <div class="spotlight-main">
                    <div id="spotlight-title" class="spotlight-label spotlight-label-open">
                        <i class="bi bi-pause-circle" aria-hidden="true"></i>還沒寫完
                    </div>
                    <div class="exam-title spotlight-name">{{ openAttemptExam.name }}</div>
                    <div class="spotlight-meta">
                        <span>{{ formatWhen(openAttemptExam.open_attempt.updated_at) }}中斷</span>
                        <span>進度已自動儲存</span>
                    </div>
                    <div class="spotlight-actions">
                        <button type="button" class="action action-primary action-lg" @click="openExam(openAttemptExam.id)">
                            繼續作答（從第 {{ openAttemptExam.open_attempt.current_position }} 題）
                        </button>
                        <button type="button" class="action action-quiet action-lg" @click="abandonTarget = openAttemptExam">放棄這次作答</button>
                    </div>
                </div>
                <div class="spotlight-figure">
                    <div class="big-number">
                        <span class="big-value">{{ openAttemptExam.open_attempt.answered_count }}</span>
                        <span class="big-total">/ {{ openAttemptExam.open_attempt.question_count }}</span>
                        <span class="big-caption">題已作答</span>
                    </div>
                    <div class="bar" aria-hidden="true">
                        <div class="bar-fill" :style="{ width: percent(openAttemptExam.open_attempt.answered_count, openAttemptExam.open_attempt.question_count) + '%' }"></div>
                    </div>
                    <div class="figure-foot">
                        <span>{{ timeLeftText(openAttemptExam.open_attempt) }}</span>
                        <span v-if="openAttemptExam.open_attempt.flagged_count">{{ openAttemptExam.open_attempt.flagged_count }} 題標記待複查</span>
                    </div>
                </div>
            </section>

            <section v-else-if="lastPractisedExam" class="spotlight" aria-labelledby="spotlight-title">
                <div class="spotlight-main">
                    <div id="spotlight-title" class="spotlight-label">上次練習的考卷</div>
                    <div class="exam-title spotlight-name">{{ lastPractisedExam.name }}</div>
                    <div class="spotlight-meta">
                        <span>{{ formatDay(lastPractisedExam.last_result.completed_at) }}作答</span>
                        <span v-if="lastPractisedExam.last_result.duration_seconds">用時 {{ formatDuration(lastPractisedExam.last_result.duration_seconds) }}</span>
                        <span>{{ lastPractisedExam.question_count }} 題<template v-if="lastPractisedExam.time_limit">，限時 {{ lastPractisedExam.time_limit }} 分鐘</template></span>
                    </div>
                    <div class="spotlight-actions">
                        <button type="button" class="action action-primary action-lg" @click="openExam(lastPractisedExam.id)">再做一次</button>
                    </div>
                </div>
                <div class="spotlight-figure">
                    <div class="big-number">
                        <span class="big-value">{{ lastPractisedExam.last_result.correct_count }}</span>
                        <span class="big-total">/ {{ lastPractisedExam.last_result.total_count }}</span>
                        <span class="big-caption">答對 {{ percent(lastPractisedExam.last_result.correct_count, lastPractisedExam.last_result.total_count) }}%</span>
                    </div>
                    <div class="bar" aria-hidden="true">
                        <div class="bar-fill" :style="{ width: percent(lastPractisedExam.last_result.correct_count, lastPractisedExam.last_result.total_count) + '%' }"></div>
                    </div>
                    <div class="figure-foot">
                        <span>答錯 {{ lastPractisedExam.last_result.total_count - lastPractisedExam.last_result.correct_count }} 題</span>
                    </div>
                </div>
            </section>

            <!-- All exams -->
            <section class="exam-list" aria-labelledby="list-title">
                <div class="list-head">
                    <h2 id="list-title">全部考卷</h2>
                    <label class="sort">
                        排序
                        <select v-model="sortBy">
                            <option value="created">最近建立</option>
                            <option value="activity">最近作答</option>
                            <option value="name">名稱</option>
                        </select>
                    </label>
                </div>
                <div class="list-columns" aria-hidden="true">
                    <div>考卷</div><div>題數</div><div>時間</div><div>最近成績</div><div>建立</div><div class="col-actions">動作</div>
                </div>
                <ul class="exam-rows">
                    <li v-for="exam in sortedExams" :key="exam.id" class="exam-row">
                        <div class="exam-title row-name">{{ exam.name }}</div>
                        <div class="row-meta">{{ exam.question_count }} 題</div>
                        <div class="row-meta">{{ exam.time_limit ? `${exam.time_limit} 分鐘` : '不限時' }}</div>
                        <div class="row-score">
                            <span v-if="exam.open_attempt" class="chip-open">
                                <i class="bi bi-pause-fill" aria-hidden="true"></i>寫到第 {{ exam.open_attempt.current_position }} / {{ exam.open_attempt.question_count }} 題
                            </span>
                            <template v-else-if="exam.last_result">
                                <div class="score-line">
                                    <span>{{ exam.last_result.correct_count }} / {{ exam.last_result.total_count }}（{{ percent(exam.last_result.correct_count, exam.last_result.total_count) }}%）</span>
                                    <span class="muted">{{ formatShortDate(exam.last_result.completed_at) }}</span>
                                </div>
                                <div class="bar bar-thin" aria-hidden="true">
                                    <div class="bar-fill" :style="{ width: percent(exam.last_result.correct_count, exam.last_result.total_count) + '%' }"></div>
                                </div>
                            </template>
                            <span v-else class="muted">還沒作答</span>
                        </div>
                        <div class="row-meta muted">{{ formatDate(exam.created_at) }}</div>
                        <div class="row-actions">
                            <button type="button" class="action" :class="exam.open_attempt ? 'action-primary' : 'action-outline'" @click="openExam(exam.id)">
                                {{ exam.open_attempt ? '繼續作答' : '開始作答' }}
                            </button>
                            <button type="button" class="icon-btn" :aria-label="`列印「${exam.name}」`" title="列印" @click="printExam(exam.id)">
                                <i class="bi bi-printer" aria-hidden="true"></i>
                            </button>
                            <button v-if="exam.is_owner" type="button" class="icon-btn" :aria-label="`刪除「${exam.name}」`" title="刪除"
                                @click="deleteTarget = exam">
                                <i class="bi bi-trash3" aria-hidden="true"></i>
                            </button>
                        </div>
                    </li>
                </ul>
            </section>
        </template>

        <!-- Confirm: delete an exam the user owns -->
        <div v-if="deleteTarget" class="overlay" @click.self="deleteTarget = null">
            <div class="dialog" role="alertdialog" aria-modal="true" aria-labelledby="del-title" aria-describedby="del-desc">
                <h2 id="del-title">刪除這份考卷？</h2>
                <p id="del-desc">「{{ deleteTarget.name }}」會從你的考卷中移除。題目本身還留在題庫。</p>
                <p v-if="actionError" class="dialog-error" role="alert">{{ actionError }}</p>
                <div class="dialog-actions">
                    <button type="button" class="action action-outline" @click="deleteTarget = null; actionError = ''">取消</button>
                    <button type="button" class="action action-danger" :disabled="busy" @click="confirmDelete">
                        {{ busy ? '刪除中…' : '刪除考卷' }}
                    </button>
                </div>
            </div>
        </div>

        <!-- Confirm: abandon an unfinished attempt -->
        <div v-if="abandonTarget" class="overlay" @click.self="abandonTarget = null">
            <div class="dialog" role="alertdialog" aria-modal="true" aria-labelledby="ab-title" aria-describedby="ab-desc">
                <h2 id="ab-title">放棄這次作答？</h2>
                <p id="ab-desc">已作答的 {{ abandonTarget.open_attempt.answered_count }} 題會清除，不會計入成績。考卷本身還在，之後可以重新開始。</p>
                <p v-if="actionError" class="dialog-error" role="alert">{{ actionError }}</p>
                <div class="dialog-actions">
                    <button type="button" class="action action-outline" @click="abandonTarget = null; actionError = ''">繼續保留</button>
                    <button type="button" class="action action-danger" :disabled="busy" @click="confirmAbandon">
                        {{ busy ? '處理中…' : '放棄作答' }}
                    </button>
                </div>
            </div>
        </div>

        <!-- Random mock exam -->
        <div v-if="showMockExamModal" class="overlay" @click.self="closeMockExamModal">
            <div class="dialog dialog-wide" role="dialog" aria-modal="true" aria-labelledby="mock-title" aria-describedby="mock-desc">
                <div class="dialog-head">
                    <h2 id="mock-title" class="exam-title">隨機模擬考</h2>
                    <button type="button" class="icon-btn" aria-label="關閉" @click="closeMockExamModal">
                        <i class="bi bi-x-lg" aria-hidden="true"></i>
                    </button>
                </div>
                <p id="mock-desc">從你選的考卷裡隨機抽題，組成一份新的考卷。</p>

                <div v-if="loadingAvailableExams" class="state-inline" role="status">載入考卷中…</div>
                <p v-else-if="!availableExams.length" class="muted">目前沒有可以抽題的考卷。</p>
                <template v-else>
                    <fieldset class="field">
                        <div class="field-head">
                            <legend>從哪些考卷抽題</legend>
                            <button type="button" class="action action-quiet action-sm" @click="toggleAllSources">
                                {{ allSourcesSelected ? '全部取消' : '全選' }}
                            </button>
                        </div>
                        <div class="source-list">
                            <label v-for="exam in availableExams" :key="exam.id" class="source"
                                :class="{ selected: selectedExamIdsForMock.includes(exam.id) }">
                                <input v-model="selectedExamIdsForMock" type="checkbox" :value="exam.id">
                                <span class="source-name">{{ exam.name }}</span>
                                <span class="muted">{{ exam.question_count }} 題</span>
                            </label>
                        </div>
                    </fieldset>

                    <fieldset class="field">
                        <legend>抽幾題</legend>
                        <div class="count-chips">
                            <button v-for="count in MOCK_COUNTS" :key="count" type="button" class="chip"
                                :class="{ active: mockQuestionCount === count }" :aria-pressed="mockQuestionCount === count"
                                @click="mockQuestionCount = count">
                                {{ count }} 題
                            </button>
                        </div>
                    </fieldset>

                    <p class="mock-summary" aria-live="polite">{{ mockSummary }}</p>
                </template>

                <div class="dialog-actions dialog-actions-split">
                    <button type="button" class="action action-outline" @click="closeMockExamModal">取消</button>
                    <button type="button" class="action action-primary" :disabled="!mockPool || creatingMockExam" @click="confirmMockExam">
                        {{ creatingMockExam ? '抽題中…' : mockPool ? `抽題並建立考卷（${mockDrawCount} 題）` : '抽題並建立考卷' }}
                    </button>
                </div>
            </div>
        </div>
    </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useExamStore } from '@/stores/examStore'
import examService from '@/services/examService'
import { clearAttempt } from '@/lib/examAttemptStorage'

const router = useRouter()
const examStore = useExamStore()

const MOCK_COUNTS = [10, 20, 30, 50]

const exams = ref([])
const loading = ref(true)
const loadError = ref('')
const sortBy = ref('created')

const deleteTarget = ref(null)
const abandonTarget = ref(null)
const busy = ref(false)
const actionError = ref('')

// ---- Data ----------------------------------------------------------------

const loadExams = async () => {
    loading.value = true
    loadError.value = ''
    try {
        const { data } = await examService.getMyExams()
        exams.value = data
    } catch (err) {
        console.error('載入考卷失敗:', err)
        loadError.value = '考卷載入失敗，請確認網路後重新載入。'
    } finally {
        loading.value = false
    }
}

const time = (value) => (value ? new Date(value).getTime() : 0)
const lastActivity = (exam) =>
    Math.max(time(exam.created_at), time(exam.last_result?.completed_at), time(exam.open_attempt?.updated_at))

// The most recently touched unfinished attempt goes on top
const openAttemptExam = computed(() => {
    const open = exams.value.filter((e) => e.open_attempt)
    return open.sort((a, b) => time(b.open_attempt.updated_at) - time(a.open_attempt.updated_at))[0] || null
})

const lastPractisedExam = computed(() => {
    const done = exams.value.filter((e) => e.last_result)
    return done.sort((a, b) => time(b.last_result.completed_at) - time(a.last_result.completed_at))[0] || null
})

const sortedExams = computed(() => {
    const list = [...exams.value]
    if (sortBy.value === 'name') return list.sort((a, b) => a.name.localeCompare(b.name, 'zh-Hant'))
    if (sortBy.value === 'activity') return list.sort((a, b) => lastActivity(b) - lastActivity(a))
    return list.sort((a, b) => time(b.created_at) - time(a.created_at))
})

// ---- Formatting ------------------------------------------------------------

const percent = (part, whole) => (whole ? Math.round((part / whole) * 100) : 0)

const pad = (n) => String(n).padStart(2, '0')

const formatDate = (value) => {
    if (!value) return '-'
    const d = new Date(value)
    return `${d.getFullYear()}/${pad(d.getMonth() + 1)}/${pad(d.getDate())}`
}

const formatShortDate = (value) => {
    if (!value) return ''
    const d = new Date(value)
    return `${d.getMonth() + 1}/${pad(d.getDate())}`
}

const isToday = (d) => d.toDateString() === new Date().toDateString()

// "9 月 26 日"
const formatDay = (value) => {
    const d = new Date(value)
    return isToday(d) ? '今天' : `${d.getMonth() + 1} 月 ${d.getDate()} 日`
}

// "今天 14:32 " / "9 月 26 日 14:32 "
const formatWhen = (value) => {
    const d = new Date(value)
    return `${formatDay(value)} ${pad(d.getHours())}:${pad(d.getMinutes())} `
}

const formatDuration = (seconds) => {
    const minutes = Math.round(seconds / 60)
    return minutes >= 1 ? `${minutes} 分鐘` : `${seconds} 秒`
}

const timeLeftText = (attempt) => {
    if (!attempt.time_limit_seconds) return '不限時'
    const left = Math.max(0, attempt.time_limit_seconds - attempt.elapsed_seconds)
    if (left === 0) return '時間已用完'
    return left >= 60 ? `還剩 ${Math.floor(left / 60)} 分鐘` : `還剩 ${left} 秒`
}

// ---- Actions ---------------------------------------------------------------

// The exam page asks whether to continue an unfinished attempt
const openExam = (examId) => router.push(`/exams/${examId}/preview`)

const printExam = (examId) => {
    const url = router.resolve({ path: `/admin/exams/${examId}/print` }).href
    window.open(url, '_blank')
}

const confirmDelete = async () => {
    busy.value = true
    actionError.value = ''
    try {
        await examStore.deleteExam(deleteTarget.value.id)
        clearAttempt(deleteTarget.value.id)
        deleteTarget.value = null
        await loadExams()
    } catch (err) {
        console.error('刪除考卷失敗:', err)
        actionError.value = '刪除失敗，請稍後再試。'
    } finally {
        busy.value = false
    }
}

const confirmAbandon = async () => {
    busy.value = true
    actionError.value = ''
    try {
        await examService.abandonExamAttempt(abandonTarget.value.open_attempt.id)
        clearAttempt(abandonTarget.value.id)
        abandonTarget.value = null
        await loadExams()
    } catch (err) {
        console.error('放棄作答失敗:', err)
        actionError.value = '現在連不上伺服器，作答沒有放棄。請確認網路後再試一次。'
    } finally {
        busy.value = false
    }
}

// ---- Random mock exam --------------------------------------------------------

const showMockExamModal = ref(false)
const availableExams = ref([])
const loadingAvailableExams = ref(false)
const selectedExamIdsForMock = ref([])
const mockQuestionCount = ref(30)
const creatingMockExam = ref(false)

const mockPool = computed(() =>
    availableExams.value
        .filter((e) => selectedExamIdsForMock.value.includes(e.id))
        .reduce((sum, e) => sum + (e.question_count || 0), 0)
)
const mockDrawCount = computed(() => Math.min(mockQuestionCount.value, mockPool.value))
const allSourcesSelected = computed(() =>
    availableExams.value.length > 0 && selectedExamIdsForMock.value.length === availableExams.value.length
)

const mockSummary = computed(() => {
    if (!mockPool.value) return '先選至少一份考卷。'
    const note = mockQuestionCount.value > mockPool.value ? `（只有 ${mockPool.value} 題，全部都會抽到）` : ''
    return `從 ${mockPool.value} 題中隨機抽 ${mockDrawCount.value} 題${note}。重複的題目只算一次。`
})

const toggleAllSources = () => {
    selectedExamIdsForMock.value = allSourcesSelected.value ? [] : availableExams.value.map((e) => e.id)
}

const openMockExamModal = async () => {
    showMockExamModal.value = true
    loadingAvailableExams.value = true
    selectedExamIdsForMock.value = []
    try {
        // Published exams plus the user's own
        const res = await examStore.getPracticeExams({ page_size: 100 })
        const list = res.data?.results || res.data || []
        availableExams.value = list.filter((e) => (e.question_count || 0) > 0)
    } catch (err) {
        console.error('Failed to load exams:', err)
        availableExams.value = []
    } finally {
        loadingAvailableExams.value = false
    }
}

const closeMockExamModal = () => {
    showMockExamModal.value = false
    selectedExamIdsForMock.value = []
}

const confirmMockExam = async () => {
    if (!mockPool.value) return
    creatingMockExam.value = true
    try {
        const ids = new Set()
        for (const examId of selectedExamIdsForMock.value) {
            try {
                const { data } = await examStore.getExam(examId)
                for (const eq of data?.exam_questions || []) if (eq.question) ids.add(eq.question)
            } catch (err) {
                console.error(`Failed to fetch exam ${examId}:`, err)
            }
        }
        const shuffled = [...ids]
        for (let i = shuffled.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            ;[shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]]
        }
        const picked = shuffled.slice(0, mockQuestionCount.value)
        if (!picked.length) return
        closeMockExamModal()
        // The create page opens with these questions filled in, ready to name and save
        router.push({ path: '/exams/create', query: { preload_questions: picked.join(',') } })
    } finally {
        creatingMockExam.value = false
    }
}

onMounted(loadExams)

defineExpose({ exams, loadExams })
</script>

<style scoped>
.my-exams {
    max-width: 1120px;
    margin: 0 auto;
    padding: 32px 16px 48px;
    display: flex;
    flex-direction: column;
    gap: 28px;
    color: var(--text-primary);
}

.exam-title {
    font-family: 'Noto Serif TC', 'Source Han Serif TC', 'Songti TC', 'PMingLiU', serif;
    font-weight: 700;
}

.muted {
    color: var(--text-muted);
}

/* ---- Buttons ---- */
.action {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-height: 40px;
    padding: 0 16px;
    border-radius: 10px;
    border: 1px solid transparent;
    font: inherit;
    font-size: 15px;
    font-weight: 500;
    white-space: nowrap;
    cursor: pointer;
}

.action:disabled {
    opacity: 0.55;
    cursor: not-allowed;
}

.action-lg {
    min-height: 44px;
    padding: 0 20px;
}

.action-sm {
    min-height: 36px;
    padding: 0 10px;
    font-size: 14px;
}

.action-primary {
    background: var(--primary);
    color: var(--on-primary);
}

.action-primary:hover:not(:disabled) {
    background: var(--primary-hover);
}

.action-outline {
    background: var(--surface);
    border-color: var(--border-strong);
    color: var(--text-primary);
}

.action-outline:hover:not(:disabled) {
    background: var(--surface-hover);
}

.action-quiet {
    background: transparent;
    color: var(--text-secondary);
}

.action-quiet:hover:not(:disabled) {
    color: var(--text-primary);
    background: var(--surface-hover);
}

.action-danger {
    background: var(--danger);
    color: var(--on-primary);
}

.icon-btn {
    width: 40px;
    height: 40px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: 0;
    border-radius: 8px;
    background: transparent;
    color: var(--text-secondary);
    font-size: 17px;
    cursor: pointer;
}

.icon-btn:hover {
    background: var(--surface-hover);
    color: var(--text-primary);
}

/* ---- Page head ---- */
.page-head {
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
    gap: 16px;
    flex-wrap: wrap;
}

.page-title-group {
    display: flex;
    align-items: baseline;
    gap: 14px;
}

.page-title {
    margin: 0;
    font-family: 'Noto Serif TC', 'Source Han Serif TC', 'Songti TC', 'PMingLiU', serif;
    font-size: 32px;
    font-weight: 700;
}

.page-count {
    font-size: 15px;
    color: var(--text-secondary);
}

.page-actions {
    display: flex;
    gap: 10px;
}

.page-actions .action {
    min-height: 44px;
}

/* ---- Loading / error / empty ---- */
.state-panel {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    padding: 64px 24px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 16px;
    color: var(--text-secondary);
}

.spinner {
    width: 32px;
    height: 32px;
    border: 3px solid var(--surface-muted);
    border-top-color: var(--primary);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
}

@keyframes spin {
    to { transform: rotate(360deg); }
}

@media (prefers-reduced-motion: reduce) {
    .spinner { animation-duration: 2.4s; }
}

.empty-panel {
    display: grid;
    grid-template-columns: 200px minmax(0, 1fr);
    gap: 48px;
    align-items: center;
    padding: 48px 56px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 16px;
}

.empty-art .art-back { fill: var(--surface-muted); stroke: var(--border-strong); stroke-width: 2; }
.empty-art .art-front { fill: var(--surface); stroke: var(--border-strong); stroke-width: 2; }
.empty-art .art-lines { stroke: var(--border-strong); stroke-width: 3; stroke-linecap: round; }
.empty-art .art-badge { fill: var(--primary); }
.empty-art .art-plus { stroke: var(--on-primary); stroke-width: 3.5; stroke-linecap: round; }

.empty-copy {
    display: flex;
    flex-direction: column;
    gap: 14px;
    max-width: 560px;
}

.empty-copy h2 {
    margin: 0;
    font-family: 'Noto Serif TC', 'Source Han Serif TC', 'Songti TC', 'PMingLiU', serif;
    font-size: 26px;
}

.empty-copy p {
    margin: 0;
    font-size: 16px;
    line-height: 1.8;
    color: var(--text-secondary);
}

.empty-actions {
    display: flex;
    gap: 10px;
    margin-top: 8px;
    flex-wrap: wrap;
}

/* ---- Spotlight ---- */
.spotlight {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 300px;
    gap: 40px;
    align-items: center;
    padding: 28px 32px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 16px;
}

.spotlight-open {
    border: 2px solid var(--primary);
}

.spotlight-main {
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-width: 0;
}

.spotlight-label {
    font-size: 14px;
    font-weight: 500;
    color: var(--text-secondary);
}

.spotlight-label-open {
    display: flex;
    align-items: center;
    gap: 6px;
    font-weight: 700;
    color: var(--primary-text);
}

.spotlight-name {
    font-size: 26px;
    line-height: 1.35;
}

.spotlight-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 6px 18px;
    font-size: 14px;
    color: var(--text-secondary);
}

.spotlight-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    margin-top: 10px;
}

.spotlight-figure {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.big-number {
    display: flex;
    align-items: baseline;
    gap: 6px;
    font-family: 'Noto Serif TC', 'Source Han Serif TC', 'Songti TC', 'PMingLiU', serif;
    font-variant-numeric: tabular-nums;
}

.big-value {
    font-size: 64px;
    font-weight: 700;
    line-height: 1;
}

.big-total {
    font-size: 26px;
    font-weight: 600;
    color: var(--text-secondary);
}

.big-caption {
    margin-left: auto;
    font-family: inherit;
    font-size: 15px;
    color: var(--text-secondary);
}

.bar {
    height: 8px;
    border-radius: 999px;
    background: var(--surface-muted);
    overflow: hidden;
}

.bar-thin {
    height: 6px;
}

.bar-fill {
    height: 100%;
    border-radius: 999px;
    background: var(--primary);
}

.figure-foot {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    font-size: 14px;
    color: var(--text-secondary);
    font-variant-numeric: tabular-nums;
}

/* ---- List ---- */
.exam-list {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 16px;
    overflow: hidden;
}

.list-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 18px 24px;
}

.list-head h2 {
    margin: 0;
    font-size: 17px;
    font-weight: 700;
}

.sort {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 14px;
    color: var(--text-secondary);
}

.sort select {
    height: 36px;
    padding: 0 10px;
    border-radius: 8px;
    border: 1px solid var(--border-strong);
    background: var(--surface);
    color: var(--text-primary);
    font: inherit;
    font-size: 14px;
}

.list-columns,
.exam-row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 72px 96px 210px 104px 196px;
    gap: 16px;
    align-items: center;
    padding: 0 24px;
}

.list-columns {
    padding-top: 10px;
    padding-bottom: 10px;
    background: var(--surface-muted);
    font-size: 13px;
    font-weight: 500;
    color: var(--text-secondary);
}

.col-actions {
    text-align: right;
}

.exam-rows {
    margin: 0;
    padding: 0;
    list-style: none;
}

.exam-row {
    padding-top: 14px;
    padding-bottom: 14px;
    border-top: 1px solid var(--border);
    font-variant-numeric: tabular-nums;
}

.row-name {
    font-size: 16px;
    font-weight: 600;
    line-height: 1.4;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.row-meta {
    font-size: 14px;
    color: var(--text-secondary);
}

.row-score {
    display: flex;
    flex-direction: column;
    gap: 6px;
    font-size: 14px;
}

.score-line {
    display: flex;
    justify-content: space-between;
    gap: 8px;
}

.chip-open {
    align-self: flex-start;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 4px 10px;
    border-radius: 999px;
    background: var(--primary-soft);
    color: var(--primary-text);
    font-size: 13px;
    font-weight: 500;
}

.row-actions {
    display: flex;
    justify-content: flex-end;
    gap: 6px;
}

/* ---- Dialogs ---- */
.overlay {
    position: fixed;
    inset: 0;
    z-index: 1000;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 16px;
    background: var(--overlay);
}

.dialog {
    width: 100%;
    max-width: 440px;
    max-height: calc(100vh - 32px);
    overflow-y: auto;
    box-sizing: border-box;
    padding: 28px;
    display: flex;
    flex-direction: column;
    gap: 14px;
    background: var(--surface-raised);
    border: 1px solid var(--border);
    border-radius: 16px;
}

.dialog-wide {
    max-width: 560px;
}

.dialog h2 {
    margin: 0;
    font-size: 19px;
    font-weight: 700;
}

.dialog p {
    margin: 0;
    font-size: 15px;
    line-height: 1.7;
    color: var(--text-secondary);
}

.dialog .dialog-error {
    padding: 8px 12px;
    border-radius: 8px;
    background: var(--danger-soft);
    color: var(--danger);
    font-size: 14px;
}

.dialog-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.dialog-head h2 {
    font-size: 22px;
}

.dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: 10px;
    margin-top: 8px;
}

.dialog-actions-split {
    padding-top: 16px;
    border-top: 1px solid var(--border);
}

.field {
    margin: 4px 0 0;
    padding: 0;
    border: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
}

.field legend {
    padding: 0;
    font-size: 15px;
    font-weight: 700;
    color: var(--text-primary);
}

.field-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.source-list {
    display: flex;
    flex-direction: column;
    max-height: 290px;
    overflow-y: auto;
    border: 1px solid var(--border);
    border-radius: 12px;
}

.source {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 48px;
    padding: 0 16px;
    cursor: pointer;
    font-size: 15px;
    font-variant-numeric: tabular-nums;
}

.source + .source {
    border-top: 1px solid var(--border);
}

.source.selected {
    background: var(--primary-soft);
}

.source input {
    width: 18px;
    height: 18px;
    margin: 0;
    accent-color: var(--primary);
}

.source-name {
    flex: 1;
    min-width: 0;
}

.count-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
}

.chip {
    min-width: 76px;
    min-height: 44px;
    padding: 0 16px;
    border-radius: 10px;
    border: 1px solid var(--border-strong);
    background: transparent;
    color: var(--text-primary);
    font: inherit;
    font-size: 15px;
    font-variant-numeric: tabular-nums;
    cursor: pointer;
}

.chip.active {
    border-color: var(--primary);
    background: var(--primary);
    color: var(--on-primary);
    font-weight: 500;
}

.dialog .mock-summary {
    font-size: 14px;
}

.state-inline {
    padding: 24px 0;
    color: var(--text-secondary);
}

/* ---- Tablet / phone ---- */
@media (max-width: 960px) {
    .spotlight {
        grid-template-columns: minmax(0, 1fr);
        gap: 20px;
    }

    .list-columns {
        display: none;
    }

    /* Each exam becomes a stacked block: name, then 題數 + 時間 on one line,
       then the latest score, then the actions. The created date is dropped. */
    .exam-row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 8px 14px;
        padding: 16px;
    }

    .row-name {
        flex: 0 0 100%;
        white-space: normal;
    }

    .exam-row > .row-meta:nth-child(5) {
        display: none;
    }

    .row-score {
        flex: 0 0 100%;
    }

    .row-actions {
        flex: 0 0 100%;
        justify-content: flex-start;
    }

    .row-actions .action {
        min-height: 44px;
    }

    .icon-btn {
        width: 44px;
        height: 44px;
    }
}

@media (max-width: 640px) {
    .my-exams {
        padding-top: 20px;
        gap: 20px;
    }

    .page-title {
        font-size: 26px;
    }

    .page-actions {
        width: 100%;
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .spotlight {
        padding: 18px;
    }

    .spotlight-name {
        font-size: 19px;
    }

    .big-value {
        font-size: 44px;
    }

    .big-total {
        font-size: 20px;
    }

    .spotlight-actions .action {
        flex: 1 1 100%;
    }

    .empty-panel {
        grid-template-columns: minmax(0, 1fr);
        gap: 20px;
        padding: 28px 20px;
        justify-items: center;
    }

    .empty-art {
        width: 140px;
        height: 112px;
    }

    .list-head {
        padding: 16px;
    }
}
</style>
