<template>
  <div 
    class="timer-component" 
    :class="timerClass"
    role="timer"
    :aria-label="`Time remaining: ${formattedTime}`"
    :aria-live="timerClass === 'danger' ? 'assertive' : 'polite'"
    aria-atomic="true"
  >
    <span class="timer-label" id="timer-label">Time Remaining:</span>
    <span 
      class="timer-value" 
      aria-labelledby="timer-label"
      :aria-description="timerDescription"
    >
      {{ formattedTime }}
    </span>
    <span class="sr-only" v-if="timerClass === 'warning'">Warning: Less than 5 minutes remaining</span>
    <span class="sr-only" v-if="timerClass === 'danger'">Critical: Less than 1 minute remaining</span>
  </div>
</template>

<script setup>
import { computed, watch } from 'vue'

/**
 * TimerComponent
 * Shows the time left, given the limit and how much of it has been used.
 * It does not keep time itself: the parent owns the clock (useExamClock), so the
 * countdown pauses and resumes together with the exam.
 * Emits each threshold once, when the time left crosses it.
 */

const props = defineProps({
  timeLimit: {
    type: Number,
    required: true // in seconds
  },
  elapsed: {
    type: Number,
    default: 0 // seconds already used
  }
})

const emit = defineEmits(['time-warning', 'time-critical', 'time-expired'])

const timeLeft = computed(() => Math.max(0, props.timeLimit - Math.floor(props.elapsed)))

const formattedTime = computed(() => {
  const minutes = Math.floor(timeLeft.value / 60).toString().padStart(2, '0')
  const seconds = (timeLeft.value % 60).toString().padStart(2, '0')
  return `${minutes}:${seconds}`
})

const timerClass = computed(() => {
  if (timeLeft.value <= 60) return 'danger'
  if (timeLeft.value <= 300) return 'warning'
  return 'normal'
})

const timerDescription = computed(() => {
  if (timeLeft.value <= 60) return 'Critical: Less than 1 minute remaining'
  if (timeLeft.value <= 300) return 'Warning: Less than 5 minutes remaining'
  return 'Normal time remaining'
})

// Emit when the countdown crosses a threshold (not when it starts past one:
// a resumed exam that is already under 5 minutes shouldn't re-warn).
watch(timeLeft, (left, before) => {
  if (before > 300 && left <= 300 && left > 60) emit('time-warning', left)
  if (before > 60 && left <= 60 && left > 0) emit('time-critical', left)
  if (before > 0 && left === 0) emit('time-expired')
})

defineExpose({ timeLeft })
</script>

<style scoped>
.timer-component {
  font-weight: bold;
  font-size: 18px;
  padding: 8px 16px;
  border-radius: 6px;
  transition: all 0.3s ease;
}

.timer-component.normal {
  color: var(--primary-text);
  background: var(--primary-soft);
}

.timer-component.warning {
  color: var(--warning);
  background: var(--warning-soft);
}

.timer-component.danger {
  color: var(--danger);
  background: var(--danger-soft);
  animation: pulse 1s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.7; }
}

.timer-label {
  margin-right: 8px;
}

.timer-value {
  font-family: 'Courier New', monospace;
  font-size: 20px;
}

/* Screen reader only class for accessibility */
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
.timer-component:focus {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}

/* High contrast mode support */
@media (prefers-contrast: high) {
  .timer-component.normal {
    border: 2px solid var(--primary);
  }
  
  .timer-component.warning {
    border: 2px solid var(--warning);
  }
  
  .timer-component.danger {
    border: 2px solid var(--danger);
  }
}

/* Reduced motion support */
@media (prefers-reduced-motion: reduce) {
  .timer-component.danger {
    animation: none;
  }
}

/* Tablet breakpoint */
@media (max-width: 768px) {
  .timer-component {
    font-size: 16px;
    padding: 8px 14px;
  }
  
  .timer-value {
    font-size: 18px;
  }
}

/* Mobile breakpoint */
@media (max-width: 480px) {
  .timer-component {
    font-size: 14px;
    padding: 6px 12px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
  }
  
  .timer-label {
    margin-right: 0;
    font-size: 12px;
  }
  
  .timer-value {
    font-size: 20px;
  }
}

/* Extra small screens - compact mode */
@media (max-width: 360px) {
  .timer-component {
    padding: 4px 10px;
  }
  
  .timer-label {
    display: none;
  }
  
  .timer-value {
    font-size: 18px;
  }
}
</style>