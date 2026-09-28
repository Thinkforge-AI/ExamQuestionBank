<script setup>
import { useTheme } from '@/composables/useTheme'

defineProps({
  // Stretch the three options across the container (mobile drawer).
  block: { type: Boolean, default: false }
})

const { preference, setPreference } = useTheme()

const options = [
  { value: 'light', label: '淺色', icon: 'bi-sun' },
  { value: 'dark', label: '深色', icon: 'bi-moon' },
  { value: 'system', label: '系統', icon: 'bi-display' }
]
</script>

<template>
  <div class="theme-toggle" :class="{ block }" role="group" aria-label="外觀">
    <button
      v-for="option in options"
      :key="option.value"
      type="button"
      class="theme-option"
      :class="{ active: preference === option.value }"
      :aria-pressed="preference === option.value"
      :title="option.value === 'system' ? '依裝置設定自動切換' : undefined"
      @click="setPreference(option.value)"
    >
      <i :class="['bi', option.icon]" aria-hidden="true"></i>
      <span>{{ option.label }}</span>
    </button>
  </div>
</template>

<style scoped>
.theme-toggle {
  display: inline-flex;
  gap: 2px;
  padding: 3px;
  background: var(--surface-muted);
  border: 1px solid var(--border);
  border-radius: 10px;
}

.theme-toggle.block {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  width: 100%;
}

.theme-option {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  height: 34px;
  padding: 0 12px;
  border: 0;
  border-radius: 7px;
  background: transparent;
  color: var(--text-secondary);
  font: inherit;
  font-size: 13px;
  cursor: pointer;
}

.block .theme-option {
  height: 44px;
  font-size: 14px;
}

.theme-option:hover {
  color: var(--text-primary);
}

.theme-option.active {
  background: var(--surface);
  color: var(--text-primary);
  font-weight: 500;
  box-shadow: var(--shadow);
}

.theme-option i {
  font-size: 14px;
}
</style>
