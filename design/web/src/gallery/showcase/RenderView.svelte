<script lang="ts">
  import { onMount, tick } from "svelte";
  import ShotCanvas from "@gallery/showcase/ShotCanvas.svelte";
  import { applyScroll } from "@gallery/showcase/scroll";
  import type { Shot } from "@gallery/showcase/shots";

  let { shot, time }: { shot: Shot; time: number } = $props();

  const frames = async (count: number) => {
    for (let i = 0; i < count; i++) await new Promise(requestAnimationFrame);
  };

  const finite = (animation: Animation) =>
    Number.isFinite(Number(animation.effect?.getComputedTiming().endTime));

  /* Lets the screen finish arriving — a sheet sliding up, a fade — so the
     still matches the gallery. Sheets start a frame or two after mounting, so
     it looks again until nothing finite is left running. */
  async function settle(timeout = 4000) {
    const deadline = performance.now() + timeout;
    while (performance.now() < deadline) {
      await frames(3);
      const pending = document
        .getAnimations()
        .filter((animation) => animation.playState === "running" && finite(animation));
      if (pending.length === 0) return;
      await Promise.race([
        Promise.all(pending.map((animation) => animation.finished.catch(() => {}))),
        new Promise((resolve) => setTimeout(resolve, deadline - performance.now())),
      ]);
    }
  }

  /* Loops — the phone's float, a spinner — hold at the same moment, so a
     still is repeatable and a run of increasing times makes a video. */
  onMount(async () => {
    await document.fonts.ready;
    await tick();
    await Promise.all([...document.images].map((image) => image.decode().catch(() => {})));
    await settle();
    applyScroll(document.body, shot.scroll);
    for (const animation of document.getAnimations()) {
      if (finite(animation)) continue;
      animation.pause();
      animation.currentTime = time * 1000;
    }
    await frames(2);
    document.body.dataset.showcaseReady = "true";
  });
</script>

<div class="showcase-render">
  <ShotCanvas {shot} moving />
</div>

<style>
  .showcase-render {
    position: fixed;
    inset: 0;
  }
</style>
