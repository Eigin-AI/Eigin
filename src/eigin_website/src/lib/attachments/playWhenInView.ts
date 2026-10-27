import type { Attachment } from "svelte/attachments";

/** Pauses CSS and SVG motion when hidden, off-screen, or explicitly paused. */
export function playWhenInView(
  paused: boolean,
  onActive: (active: boolean) => void,
): Attachment<HTMLElement> {
  return (element) => {
    const top = document.querySelector<HTMLElement>(".site-header")?.offsetHeight ?? 0;
    let inView = false;
    for (const svg of element.querySelectorAll("svg")) svg.pauseAnimations();
    for (const animation of element.querySelectorAll<SVGAnimationElement>("[data-motion-delay]")) {
      if (animation.dataset.motionStarted) continue;
      animation.beginElementAt(Number(animation.dataset.motionDelay));
      animation.dataset.motionStarted = "true";
    }

    function update() {
      const active = inView && !paused && !document.hidden;
      element.dataset.active = String(active);
      element.dataset.inView = String(inView);
      onActive(active);
      for (const svg of element.querySelectorAll("svg")) {
        if (active) svg.unpauseAnimations();
        else svg.pauseAnimations();
      }
      for (const animation of element.getAnimations({ subtree: true })) {
        if (!(animation instanceof CSSAnimation)) continue;
        if (active) animation.play();
        else animation.pause();
      }
    }

    update();
    const observer = new IntersectionObserver(
      ([entry]) => {
        const rootHeight = entry.rootBounds?.height ?? Infinity;
        inView = entry.intersectionRatio > 0.98 || entry.intersectionRect.height > rootHeight * 0.9;
        update();
      },
      { rootMargin: `-${top}px 0px 0px 0px`, threshold: [0, 0.25, 0.5, 0.75, 0.9, 0.98, 1] },
    );
    observer.observe(element);
    document.addEventListener("visibilitychange", update);
    return () => {
      observer.disconnect();
      document.removeEventListener("visibilitychange", update);
    };
  };
}
