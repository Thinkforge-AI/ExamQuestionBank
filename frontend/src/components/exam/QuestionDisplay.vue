<template>
  <div class="question-display" v-if="question">
    <div class="question-header">
      <span class="question-number">Question {{ questionNumber }}</span>
      <div class="question-meta" v-if="question.subject || question.category">
        <span v-if="question.subject" class="meta-item">{{ question.subject }}</span>
        <span v-if="question.category" class="meta-item">{{ question.category }}</span>
      </div>
    </div>
    
    <div class="question-content">
      <p class="question-text">{{ question.content }}</p>
    </div>

    <div class="answer-options" v-if="question.options && question.options.length > 0">
      <div
        v-for="(option, index) in question.options"
        :key="option.id"
        class="option-item"
        :class="{ 
          selected: selectedAnswer === option.id,
          'option-hover': true 
        }"
        @click="handleOptionSelect(option.id)"
        role="button"
        :tabindex="0"
        :aria-pressed="selectedAnswer === option.id"
        :aria-label="`Option ${getOptionLabel(index)}: ${option.content}`"
        @keydown.enter="handleOptionSelect(option.id)"
        @keydown.space.prevent="handleOptionSelect(option.id)"
      >
        <span class="option-label">{{ getOptionLabel(index) }}.</span>
        <span class="option-content">{{ option.content }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
/**
 * QuestionDisplay Component
 * Displays question content and answer options with selection interface
 * Requirements: 4.1, 4.5, 7.1 - Large readable typography, responsive design, mobile touch interaction
 */

const props = defineProps({
  question: {
    type: Object,
    required: true
  },
  questionNumber: {
    type: Number,
    required: true
  },
  selectedAnswer: {
    type: Number,
    default: null
  }
})

const emit = defineEmits(['select-answer'])

const getOptionLabel = (index) => {
  return String.fromCharCode(65 + index) // A, B, C, D...
}

const handleOptionSelect = (optionId) => {
  emit('select-answer', optionId)
}
</script>

<style scoped>
.question-display {
  background: var(--surface);
  padding: 24px;
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  margin-bottom: 24px;
  max-width: 100%;
}

.question-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
  padding-bottom: 16px;
  border-bottom: 1px solid var(--border);
}

.question-number {
  font-weight: 600;
  color: var(--text-primary);
  font-size: 20px;
}

.question-meta {
  display: flex;
  gap: 12px;
}

.meta-item {
  color: var(--text-secondary);
  font-size: 14px;
  background: var(--surface-muted);
  padding: 4px 8px;
  border-radius: 4px;
  font-weight: 500;
}

.question-content {
  margin-bottom: 24px;
}

.question-text {
  font-size: 20px;
  line-height: 1.7;
  color: var(--text-primary);
  margin: 0;
  font-weight: 400;
  letter-spacing: 0.01em;
}

.answer-options {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.option-item {
  display: flex;
  align-items: flex-start;
  gap: 14px;
  padding: 18px;
  border: 2px solid var(--border);
  border-radius: 10px;
  cursor: pointer;
  transition: all 0.2s ease;
  min-height: 64px;
  background: var(--surface);
  position: relative;
}

.option-item.option-hover:hover {
  border-color: var(--primary);
  background: var(--primary-soft);
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.15);
}

.option-item.selected {
  border-color: var(--primary);
  background: var(--primary-soft);
  box-shadow: 0 2px 8px rgba(37, 99, 235, 0.2);
}

.option-item:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.1);
}

.option-item:active {
  transform: translateY(0);
}

.option-label {
  font-weight: 700;
  color: var(--text-primary);
  min-width: 28px;
  margin-top: 2px;
  font-size: 16px;
}

.option-content {
  flex: 1;
  color: var(--text-primary);
  line-height: 1.6;
  font-size: 16px;
}

/* Mobile responsive design for touch interaction */
@media (max-width: 768px) {
  .question-display {
    padding: 20px;
    margin-bottom: 20px;
  }
  
  .question-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
    margin-bottom: 16px;
  }
  
  .question-text {
    font-size: 18px;
    line-height: 1.6;
  }
  
  .option-item {
    padding: 16px;
    min-height: 56px;
    gap: 12px;
    /* Larger touch targets for mobile */
    min-height: 60px;
  }
  
  .option-item.option-hover:hover {
    /* Reduce hover effects on mobile to prevent sticky hover states */
    transform: none;
  }
  
  .option-content {
    font-size: 16px;
  }
  
  .meta-item {
    font-size: 13px;
    padding: 3px 6px;
  }
}

/* Extra small screens */
@media (max-width: 480px) {
  .question-display {
    padding: 16px;
  }
  
  .question-text {
    font-size: 17px;
  }
  
  .option-item {
    padding: 14px;
    min-height: 56px;
  }
  
  .option-content {
    font-size: 15px;
  }
}

/* High contrast mode support */
@media (prefers-contrast: high) {
  .option-item {
    border-width: 3px;
  }
  
  .option-item.selected {
    border-color: #000000;
    background: var(--surface);
  }
  
  .meta-item {
    border: 1px solid #6b7280;
  }
}
</style>