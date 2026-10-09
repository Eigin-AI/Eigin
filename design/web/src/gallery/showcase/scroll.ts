/* A shot remembers how far its screen is scrolled, as a percentage of the
   way down, so it holds even when the export lays the screen out a little
   differently. Screens scroll different elements — a feed, a list, a sheet —
   so the one that matters is found by shape: the tallest element that
   actually scrolls. */

/** The element on the phone that scrolls, if any. */
export function mainScroller(root: Element): HTMLElement | undefined {
  let best: HTMLElement | undefined;
  for (const element of root.querySelectorAll<HTMLElement>(".device-screen *")) {
    const { overflowY } = getComputedStyle(element);
    if (overflowY !== "auto" && overflowY !== "scroll") continue;
    if (element.scrollHeight <= element.clientHeight + 1) continue;
    if (!best || element.clientHeight > best.clientHeight) best = element;
  }
  return best;
}

const range = (scroller: HTMLElement) => scroller.scrollHeight - scroller.clientHeight;

/** How far down `scroller` is, from 0 (top) to 100 (bottom), to one decimal. */
export function scrollPercent(scroller: HTMLElement): number {
  return Math.round((scroller.scrollTop / range(scroller)) * 1000) / 10;
}

/** Scrolls the phone to `percent` of the way down; unset leaves the screen as it is. */
export function applyScroll(root: Element, percent: number | undefined) {
  if (percent === undefined) return;
  const scroller = mainScroller(root);
  if (!scroller) return;
  const top = (percent / 100) * range(scroller);
  if (Math.abs(scroller.scrollTop - top) > 1) scroller.scrollTop = top;
}
