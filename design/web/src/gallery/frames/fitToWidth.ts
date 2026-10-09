/**
 * Scales a frame down until it fits the room it has.
 *
 * A landscape phone is wider than the stage on most windows, and a frame you
 * have to scroll sideways loses the thing that makes it a frame: you cannot
 * see both bezels at once. Scaling keeps the whole device in view; it never
 * scales up, so a frame that fits is shown at its true size.
 *
 * Applied to a wrapper, which takes the scaled size as its own layout size —
 * a transform alone would leave the old box behind and throw off centering.
 * Pass `false` to keep the frame at its true size whatever the room.
 */
export function fitToWidth(node: HTMLElement, enabled = true) {
  if (!enabled) return;
  const frame = node.firstElementChild as HTMLElement | null;

  const measure = () => {
    const parent = node.parentElement;
    if (!frame || !parent) return;

    const style = getComputedStyle(parent);
    const available =
      parent.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    const natural = frame.offsetWidth;
    if (!natural || available <= 0) return;

    const scale = Math.min(1, available / natural);
    node.style.setProperty("--fit-scale", `${scale}`);
    node.style.width = `${natural * scale}px`;
    node.style.height = `${frame.offsetHeight * scale}px`;
  };

  const observer = new ResizeObserver(measure);
  observer.observe(node);
  if (node.parentElement) observer.observe(node.parentElement);
  if (frame) observer.observe(frame);
  measure();

  return {
    destroy() {
      observer.disconnect();
    },
  };
}
