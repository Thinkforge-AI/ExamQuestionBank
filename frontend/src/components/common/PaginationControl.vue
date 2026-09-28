<template>
    <nav v-if="paginationState.totalPages > 0" class="pagination-wrapper" aria-label="分頁" :aria-busy="isLoading">
        <div class="pagination-info">
            <span class="text-muted" aria-live="polite">
                共 {{ paginationState.totalCount }} 筆 | 第 {{ page }} / {{ paginationState.totalPages }} 頁
            </span>
            <select :value="pageSize" class="form-select form-select-sm page-size-select" aria-label="每頁筆數"
                @change="onPageSizeChange">
                <option v-for="size in PAGE_SIZES" :key="size" :value="size">每頁 {{ size }} 筆</option>
            </select>
        </div>

        <ul class="pagination mb-0">
            <li class="page-item" :class="{ disabled: !canPrev }">
                <button type="button" class="page-link" :disabled="!canPrev" aria-label="第一頁" title="第一頁"
                    @click="goTo(1)">
                    <span aria-hidden="true">&laquo;</span>
                </button>
            </li>
            <li class="page-item" :class="{ disabled: !canPrev }">
                <button type="button" class="page-link" :disabled="!canPrev" aria-label="上一頁" title="上一頁"
                    @click="goTo(page - 1)">
                    <span aria-hidden="true">&lsaquo;</span>
                </button>
            </li>

            <li v-for="item in visiblePages" :key="item.key" class="page-item"
                :class="{ active: item.page === page, gap: item.page === null }">
                <span v-if="item.page === null" class="page-gap" aria-hidden="true">…</span>
                <button v-else type="button" class="page-link" :disabled="isLoading"
                    :aria-current="item.page === page ? 'page' : undefined" :aria-label="`第 ${item.page} 頁`"
                    @click="goTo(item.page)">
                    {{ item.page }}
                </button>
            </li>

            <li class="page-item" :class="{ disabled: !canNext }">
                <button type="button" class="page-link" :disabled="!canNext" aria-label="下一頁" title="下一頁"
                    @click="goTo(page + 1)">
                    <span aria-hidden="true">&rsaquo;</span>
                </button>
            </li>
            <li class="page-item" :class="{ disabled: !canNext }">
                <button type="button" class="page-link" :disabled="!canNext" aria-label="最後一頁" title="最後一頁"
                    @click="goTo(paginationState.totalPages)">
                    <span aria-hidden="true">&raquo;</span>
                </button>
            </li>
        </ul>

        <form class="page-jumper" @submit.prevent="handlePageJump">
            <label :for="jumpInputId" class="text-muted">跳至</label>
            <input :id="jumpInputId" v-model.number="jumpToPage" type="number" inputmode="numeric"
                class="form-control form-control-sm" :min="1" :max="paginationState.totalPages" placeholder="頁碼" />
            <button type="submit" class="btn btn-sm btn-secondary" :disabled="isLoading || !isValidJumpPage">
                前往
            </button>
        </form>
    </nav>
</template>

<script setup lang="ts">
import { ref, computed, useId } from 'vue'
import { buildPageWindow } from '@/lib/pageWindow'

interface PaginationState {
    hasNext: boolean
    hasPrev: boolean
    totalPages: number
    totalCount: number
}

const props = defineProps<{
    paginationState: PaginationState
    currentPage: number
    pageSize: number
    isLoading?: boolean
}>()

const emit = defineEmits<{
    (e: 'page-change', page: number): void
    (e: 'size-change', size: number): void
}>()

const PAGE_SIZES = [10, 20, 50, 100]

const jumpInputId = useId()
const jumpToPage = ref<number | null>(null)

// Out-of-range input from the parent (e.g. a stale URL) is shown as the nearest real page.
const page = computed(() =>
    Math.min(Math.max(1, Math.trunc(props.currentPage) || 1), Math.max(1, props.paginationState.totalPages))
)
const canPrev = computed(() => page.value > 1 && !props.isLoading)
const canNext = computed(() => page.value < props.paginationState.totalPages && !props.isLoading)

const goTo = (target: number) => {
    const total = props.paginationState.totalPages
    if (props.isLoading || target < 1 || target > total || target === page.value) return
    emit('page-change', target)
}

const visiblePages = computed(() =>
    buildPageWindow(page.value, props.paginationState.totalPages).map((p: number | null, i: number) => ({
        page: p,
        key: p === null ? `gap-${i}` : `page-${p}`
    }))
)

const isValidJumpPage = computed(() => {
    if (!jumpToPage.value) return false
    const target = Number(jumpToPage.value)
    return Number.isInteger(target) && target >= 1 && target <= props.paginationState.totalPages
})

const onPageSizeChange = (event: Event) => {
    const select = event.target as HTMLSelectElement
    emit('size-change', parseInt(select.value))
}

const handlePageJump = () => {
    if (isValidJumpPage.value && jumpToPage.value) {
        goTo(jumpToPage.value)
        jumpToPage.value = null
    }
}
</script>

<style scoped>
/* Pagination Wrapper - Sticky & Floating */
.pagination-wrapper {
    position: sticky;
    bottom: 0;
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 16px;
    padding: 20px;
    background: var(--surface);
    border-radius: 12px 12px 0 0;
    box-shadow: 0 -2px 8px rgba(0, 0, 0, 0.08), 0 2px 4px rgba(0, 0, 0, 0.05);
    border: 1px solid var(--border, var(--border-strong));
    flex-wrap: wrap;
    z-index: 100;
    margin-top: 24px;
}

.pagination-info {
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
}

.pagination-info .text-muted {
    font-size: 14px;
    color: var(--text-secondary, var(--text-secondary));
    font-weight: 500;
}

.page-size-select {
    width: auto;
    min-width: 130px;
    padding: 8px 32px 8px 12px;
    border: 2px solid var(--border);
    border-radius: 8px;
    font-size: 13px;
    background: var(--bg-page);
    cursor: pointer;
    transition: all 0.2s ease;
    appearance: none;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%2364748B' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E");
    background-repeat: no-repeat;
    background-position: right 10px center;
    color: var(--text-primary, var(--text-primary));
}

.page-size-select:focus {
    outline: none;
    border-color: var(--primary, var(--primary));
    background-color: var(--surface);
    box-shadow: 0 0 0 3px rgba(71, 105, 150, 0.1);
}

.pagination {
    display: flex;
    padding-left: 0;
    list-style: none;
    gap: 6px;
    margin: 0;
}

.page-item {
    display: flex;
}

.page-link {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 40px;
    height: 40px;
    padding: 0 12px;
    color: var(--text-primary, var(--text-primary));
    text-decoration: none;
    background-color: var(--surface);
    border: 2px solid var(--border);
    border-radius: 8px;
    font-size: 14px;
    font-weight: 500;
    transition: all 0.2s ease;
    cursor: pointer;
}

.page-link:hover:not(:disabled) {
    background-color: var(--primary-soft, var(--primary-soft));
    border-color: var(--primary, var(--primary));
    color: var(--primary, var(--primary-text));
    transform: translateY(-1px);
}

.page-link,
.pagination-info .text-muted {
    font-variant-numeric: tabular-nums;
}

.page-gap {
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 28px;
    height: 40px;
    color: var(--text-muted);
    user-select: none;
}

.page-item.active .page-link {
    background: var(--primary, var(--primary));
    border-color: var(--primary, var(--primary));
    color: var(--on-primary);
    box-shadow: 0 2px 4px rgba(71, 105, 150, 0.2);
}

.page-link:disabled,
.page-item.disabled .page-link {
    cursor: not-allowed;
    opacity: 0.4;
    transform: none;
    color: var(--text-secondary, var(--text-secondary));
    background-color: var(--bg-page);
    border-color: var(--border);
    pointer-events: none;
}

.page-jumper {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0;
}

.page-jumper .text-muted {
    font-size: 14px;
    color: var(--text-secondary, var(--text-secondary));
    white-space: nowrap;
}

.page-jumper input {
    width: 70px;
    text-align: center;
    padding: 8px 12px;
    border: 2px solid var(--border);
    border-radius: 8px;
    font-size: 14px;
    background-color: var(--surface);
    color: var(--text-primary, var(--text-primary));
    transition: all 0.2s ease;
}

.page-jumper input:focus {
    outline: none;
    border-color: var(--primary, var(--primary));
    box-shadow: 0 0 0 3px rgba(71, 105, 150, 0.1);
}

.page-jumper .btn {
    white-space: nowrap;
    padding: 8px 16px;
    border: none;
    border-radius: 8px;
    background: var(--primary, var(--primary));
    color: var(--on-primary);
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
}

.page-jumper .btn:hover:not(:disabled) {
    background: var(--primary-hover, var(--primary-hover));
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(71, 105, 150, 0.3);
}

.page-jumper .btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    transform: none;
}

/* Responsive adjustments */
@media (max-width: 768px) {
    .pagination-wrapper {
        flex-direction: column;
        gap: 12px;
        padding: 16px;
    }

    .pagination-info,
    .pagination,
    .page-jumper {
        width: 100%;
        justify-content: center;
    }

    .pagination {
        flex-wrap: wrap;
    }

    .page-size-select {
        width: 100%;
    }
}
</style>
