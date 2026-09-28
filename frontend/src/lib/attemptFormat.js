/**
 * Wording for an unfinished exam attempt, shared by the exam page's resume
 * prompt and 我的考卷.
 */

const pad = (n) => String(n).padStart(2, '0')

const isToday = (d) => d.toDateString() === new Date().toDateString()

// "今天" / "9 月 26 日"
export function formatDay(value) {
  const d = new Date(value)
  return isToday(d) ? '今天' : `${d.getMonth() + 1} 月 ${d.getDate()} 日`
}

// "今天 14:32" / "9 月 26 日 14:32", or '' for a missing or invalid date
export function formatWhen(value) {
  const d = value ? new Date(value) : null
  if (!d || Number.isNaN(d.getTime())) return ''
  return `${formatDay(value)} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

// Time left before the limit: "25 分鐘" / "40 秒"
export function formatSecondsLeft(seconds) {
  return seconds >= 60 ? `${Math.floor(seconds / 60)} 分鐘` : `${seconds} 秒`
}
