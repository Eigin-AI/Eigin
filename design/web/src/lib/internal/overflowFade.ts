/**
 * Marks an element as scrollable only when its content overflows.
 *
 * The plain layout is used when it fits; the scrolling variant, with its fade
 * mask, appears only when it doesn't.
 *
 * Compares child layout boxes rather than `scrollHeight`, because trimmed text
 * boxes let ascenders and descenders spill outside the box without meaning the
 * content overflows.
 */
export function overflowFade(node: HTMLElement) {
  const update = () => {
    const first = node.firstElementChild as HTMLElement | null;
    const last = node.lastElementChild as HTMLElement | null;
    if (!first || !last) return;
    // Layout offsets, not client rects: a transformed ancestor (a tilted
    // phone) inflates rects but not clientHeight, which read as overflow.
    const contentHeight = last.offsetTop + last.offsetHeight - first.offsetTop;
    node.classList.toggle("is-scrollable", contentHeight > node.clientHeight + 1);
  };

  const observer = new ResizeObserver(update);
  observer.observe(node);
  for (const child of node.children) observer.observe(child);
  update();

  return {
    destroy() {
      observer.disconnect();
    },
  };
}
