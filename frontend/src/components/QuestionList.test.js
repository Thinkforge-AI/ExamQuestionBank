import { describe, it, expect, vi } from 'vitest'
import { shallowMount } from '@vue/test-utils'

vi.mock('@/lib/supabase', () => ({ supabase: {} }))

import QuestionList from './QuestionList.vue'
import QuestionFilterPanel from './common/QuestionFilterPanel.vue'

describe('QuestionList', () => {
  it('clears a source from the URL when the filters are reset', async () => {
    const wrapper = shallowMount(QuestionList, {
      props: { mode: 'practice', listMode: 'search', externalFilters: { source: 'wrong', subject: '民法' } }
    })

    wrapper.findComponent(QuestionFilterPanel).vm.$emit('reset')
    const [filters, page] = wrapper.emitted('search-questions').at(-1)
    expect(filters.source).toBe('all')
    expect(filters.subject).toBe('')
    expect(page).toBe(1)
  })
})
