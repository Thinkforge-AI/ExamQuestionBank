<template>
  <div class="answer-list-mvp">
    <div class="list-header">
      <h3>{{ answers.length }} 個回答</h3>
    </div>
    
    <div v-if="answers.length === 0" class="empty-state">
      <div class="empty-icon"><i class="bi bi-chat-dots"></i></div>
      <p>還沒有回答，成為第一個回答者吧！</p>
    </div>
    
    <template v-else>
      <AnswerCard
        v-for="answer in answers"
        :key="answer.id"
        :answer="answer"
        @unlock="handleUnlock"
        @vote="handleVote"
      />
    </template>
  </div>
</template>

<script setup>
import AnswerCard from './AnswerCard.vue'

const props = defineProps({
  answers: {
    type: Array,
    default: () => []
  }
})

const emit = defineEmits(['unlock', 'vote'])

function handleUnlock(answerId) {
  emit('unlock', answerId)
}

function handleVote(data) {
  emit('vote', data)
}
</script>

<style scoped>
.answer-list-mvp {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.list-header {
  padding-bottom: 0.75rem;
  border-bottom: 1px solid var(--border-color, var(--border));
}

.list-header h3 {
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-primary, var(--text-primary));
  margin: 0;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 2rem;
  text-align: center;
  color: var(--text-secondary, var(--text-secondary));
}

.empty-icon {
  font-size: 2rem;
  margin-bottom: 0.5rem;
}

.empty-state p {
  margin: 0;
}
</style>
