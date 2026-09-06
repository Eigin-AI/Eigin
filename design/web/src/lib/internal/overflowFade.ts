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
    const first = node.firstElementChild;
    const last = node.lastElementChild;
    if (!first || !last) return;
    const contentHeight = last.getBoundingClientRect().bottom - first.getBoundingClientRect().top;
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
