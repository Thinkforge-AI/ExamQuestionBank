/**
 * Page numbers to render in a pagination control, with `null` marking a gap.
 *
 * Always returns the same number of slots once there are enough pages, so the
 * control keeps a stable width while the user pages:
 *   1 2 3 4 5 … 833      (near the start)
 *   1 … 499 500 501 … 833 (middle)
 *   1 … 829 830 831 832 833 (near the end)
 * A gap always hides at least two pages; a lone hidden page is shown instead.
 */
export const PAGE_WINDOW_SLOTS = 7

export function buildPageWindow(current, total, slots = PAGE_WINDOW_SLOTS) {
  if (total <= 0) return []
  if (total <= slots) return Array.from({ length: total }, (_, i) => i + 1)

  const edge = slots - 2 // consecutive pages shown next to the first/last page
  const middle = slots - 4 // consecutive pages shown around the current page
  const page = Math.min(Math.max(1, current), total)

  if (page <= edge - 1) {
    return [...Array.from({ length: edge }, (_, i) => i + 1), null, total]
  }
  if (page >= total - edge + 2) {
    return [1, null, ...Array.from({ length: edge }, (_, i) => total - edge + 1 + i)]
  }
  const half = Math.floor(middle / 2)
  return [1, null, ...Array.from({ length: middle }, (_, i) => page - half + i), null, total]
}
