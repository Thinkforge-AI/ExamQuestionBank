<template>
  <nav 
    class="question-navigator"
    role="navigation"
    aria-label="Question navigation"
  >
    <h3 class="navigator-title" id="navigator-title">題目導航</h3>
    <div 
      class="question-grid"
      role="group"
      aria-labelledby="navigator-title"
      aria-describedby="navigator-status"
    >
      <button
        v-for="(question, index) in questions"
        :key="question.id"
        class="question-button"
        :class="{
          'current': index === currentIndex,
          'answered': answeredQuestions.has(index),
          'flagged': flaggedQuestions?.has(index)
        }"
        @click="$emit('navigate-to', index)"
        :aria-label="getButtonAriaLabel(index)"
        :aria-current="index === currentIndex ? 'step' : undefined"
        :aria-pressed="answeredQuestions.has(index)"
        type="button"
      >
        {{ index + 1 }}
      </button>
    </div>
    <p id="navigator-status" class="sr-only">
      {{ answeredQuestions.size }} of {{ questions.length }} questions answered
    </p>
    <!-- Legend -->
    <div class="navigator-legend">
      <span class="legend-item"><span class="legend-dot answered"></span>已作答</span>
      <span class="legend-item"><span class="legend-dot unanswered"></span>未作答</span>
      <span class="legend-item"><span class="legend-dot flagged"></span>已標記</span>
    </div>
  </nav>
</template>

<script setup>
/**
 * QuestionNavigator Component
 * Provides visual overview and navigation for exam questions
 * Requirements: 2.2, 2.3, 2.4, 7.3 - Navigation with accessibility support
 */

const props = defineProps({
  questions: {
    type: Array,
    required: true
  },
  currentIndex: {
    type: Number,
    required: true
  },
  answeredQuestions: {
    type: Set,
    required: true
  },
  flaggedQuestions: {
    type: Set,
    default: () => new Set()
  }
})

defineEmits(['navigate-to'])

const getButtonAriaLabel = (index) => {
  const questionNum = index + 1
  const isCurrent = index === props.currentIndex
  const isAnswered = props.answeredQuestions.has(index)
  const isFlagged = props.flaggedQuestions?.has(index)
  
  let label = `Question ${questionNum}`
  if (isCurrent) label += ', current question'
  if (isAnswered) label += ', answered'
  else label += ', not answered'
  if (isFlagged) label += ', flagged for review'
  
  return label
}
</script>

<style scoped>
.question-navigator {
  background: var(--surface);
  padding: 16px;
  border-radius: 8px;
  box-shadow: 0 1px 4px rgba(0,0,0,0.05);
  margin-bottom: 16px;
}

.navigator-title {
  margin: 0 0 12px 0;
  font-size: 16px;
  color: var(--text-primary);
}

.question-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(40px, 1fr));
  gap: 8px;
}

.question-button {
  width: 40px;
  height: 40px;
  border: 2px solid var(--border);
  background: var(--surface);
  border-radius: 6px;
  cursor: pointer;
  font-weight: 500;
  transition: all 0.2s;
  display: flex;
  align-items: center;
  justify-content: center;
}

.question-button:hover {
  border-color: var(--primary);
  background: var(--primary-soft);
}

.question-button.current {
  border-color: var(--primary);
  background: var(--primary);
  color: var(--on-primary);
}

.question-button.answered {
  border-color: var(--success);
  background: var(--success-soft);
  color: var(--success);
}

.question-button.current.answered {
  background: #059669;
  border-color: #059669;
  color: white;
}

.question-button.flagged {
  box-shadow: inset 0 0 0 3px #f97316;
}

.question-button.flagged.current {
  box-shadow: inset 0 0 0 3px #f97316;
}

/* Navigator Legend */
.navigator-legend {
  display: flex;
  gap: 12px;
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid var(--border);
  font-size: 12px;
  color: var(--text-secondary);
}

.legend-item {
  display: flex;
  align-items: center;
  gap: 4px;
}

.legend-dot {
  width: 12px;
  height: 12px;
  border-radius: 3px;
}

.legend-dot.answered {
  background: var(--success-soft);
  border: 2px solid var(--success);
}

.legend-dot.unanswered {
  background: var(--surface);
  border: 2px solid var(--border);
}

.legend-dot.flagged {
  background: var(--surface);
  border: 2px solid var(--border);
  box-shadow: inset 0 0 0 2px #f97316;
}

/* Screen reader only class */
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}

/* Focus styles for accessibility */
.question-button:focus {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
  z-index: 1;
}

.question-button:focus-visible {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}

/* High contrast mode support */
@media (prefers-contrast: high) {
  .question-button {
    border-width: 3px;
  }
  
  .question-button.current {
    border-color: #000;
    background: #000;
  }
  
  .question-button.answered {
    border-color: #065f46;
    background: var(--success-soft);
  }
}

/* Reduced motion support */
@media (prefers-reduced-motion: reduce) {
  .question-button {
    transition: none;
  }
}

/* Mobile responsive */
@media (max-width: 768px) {
  .question-grid {
    grid-template-columns: repeat(auto-fill, minmax(44px, 1fr));
    gap: 6px;
  }
  
  .question-button {
    width: 44px;
    height: 44px;
    min-width: 44px;
    min-height: 44px;
  }
}
</style>