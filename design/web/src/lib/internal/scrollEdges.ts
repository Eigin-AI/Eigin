/** Edge state for a scroll container; `gutter` is its scrollbar width. */
export interface ScrollEdges {
  top: boolean;
  bottom: boolean;
  gutter: number;
}

/**
 * Reports which edges of a scroll container have hidden content beyond them.
 *
 * Calls `onChange` as the position, size or content changes.
 */
export function scrollEdges(node: HTMLElement, onChange: (edges: ScrollEdges) => void) {
  const update = () => {
    onChange({
      top: node.scrollTop > 1,
      bottom: node.scrollTop + node.clientHeight < node.scrollHeight - 1,
      gutter: node.offsetWidth - node.clientWidth,
    });
  };

  node.addEventListener("scroll", update, { passive: true });
  // Children are observed once at mount; content that grows inside an
  // existing child after mount (streamed text, async rows) won't retrigger
  // `update` unless the child itself resizes the scroll height.
  const observer = new ResizeObserver(update);
  observer.observe(node);
  for (const child of node.children) observer.observe(child);
  update();

  return {
    destroy() {
      node.removeEventListener("scroll", update);
      observer.disconnect();
    },
  };
}
