import { ref, computed } from 'vue'

// Module-level state: every caller (header toggle, mobile drawer, charts…) shares it.
const STORAGE_KEY = 'theme'
const MODES = ['light', 'dark', 'system']

const media = typeof window !== 'undefined' && window.matchMedia
  ? window.matchMedia('(prefers-color-scheme: dark)')
  : null

const readStored = () => {
  try {
    const value = localStorage.getItem(STORAGE_KEY)
    return MODES.includes(value) ? value : 'system'
  } catch {
    return 'system'
  }
}

const preference = ref(readStored())
const systemDark = ref(media ? media.matches : false)
const resolved = computed(() =>
  preference.value === 'system' ? (systemDark.value ? 'dark' : 'light') : preference.value
)

const apply = (animate) => {
  const root = document.documentElement
  if (animate) {
    root.classList.add('theme-transition')
    window.setTimeout(() => root.classList.remove('theme-transition'), 250)
  }
  root.classList.toggle('dark', resolved.value === 'dark')
  root.setAttribute('data-bs-theme', resolved.value)
}

if (media) {
  media.addEventListener('change', (e) => {
    systemDark.value = e.matches
    if (preference.value === 'system') apply(true)
  })
}

// Keep tabs in sync when the preference changes elsewhere.
if (typeof window !== 'undefined') {
  window.addEventListener('storage', (e) => {
    if (e.key !== STORAGE_KEY) return
    preference.value = readStored()
    apply(false)
  })
}

const setPreference = (mode) => {
  if (!MODES.includes(mode) || mode === preference.value) return
  preference.value = mode
  try {
    localStorage.setItem(STORAGE_KEY, mode)
  } catch {
    // Storage blocked (private mode): the choice still applies for this visit.
  }
  apply(true)
}

export const initTheme = () => apply(false)

export function useTheme() {
  return {
    preference,
    resolved,
    isDark: computed(() => resolved.value === 'dark'),
    setPreference
  }
}
