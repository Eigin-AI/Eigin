<script lang="ts">
  import { MediaQuery } from "svelte/reactivity";
  import { Icon } from "@lib";
  import { gathering, splash, swallowing } from "@gallery/screens/onboarding/droplets";
  import {
    SETTLED,
    arrival,
    blob,
    face,
    mark,
    released,
    ripples,
  } from "@gallery/screens/onboarding/hatch";

  let {
    emoji,
    size = 140,
    speed = 1,
  }: {
    /** The face the agent hatches into. */
    emoji: string;
    size?: number;
    /** Time multiplier, so the moment can be watched in slow motion. */
    speed?: number;
  } = $props();

  const reduceMotion = new MediaQuery("(prefers-reduced-motion: reduce)");

  /* Seconds into the hatch. Reduced motion skips straight to the face. */
  let t = $state(0);

  $effect(() => {
    if (reduceMotion.current) {
      t = SETTLED;
      return;
    }
    const rate = speed;
    const start = performance.now();
    let frame = requestAnimationFrame(function tick(now) {
      t = ((now - start) / 1000) * rate;
      if (t < SETTLED) frame = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(frame);
  });

  const vessel = $derived(size * 0.89);
  const markSize = $derived((vessel * 40) / 56);
  /* The canvas reaches well past the vessel and off any phone screen, for the
     droplets to fall in from and the burst to spread into. */
  const canvas = $derived(size * 8);
  const radius = $derived(vessel / 2);

  const hatched = $derived(released(t));
  const entry = $derived(arrival(t));
  const faceNow = $derived(face(t));
  const markNow = $derived(mark(t));
  const droplets = $derived([...gathering(t, radius, canvas / 2), ...splash(t, radius)]);
</script>

<!--
  The agent hatching. The green circle with the mark starts working like the
  thinking indicator, breathing harder each time and squeezing the mark as it
  contracts. Through the last, droplets fall in from off screen and it
  swallows them. That squeeze takes the mark away; the blob snaps back to a
  circle, splashing, and the agent's face springs into it.
-->
<div
  class="hatch"
  style:width="{size}px"
  style:height="{size}px"
  style:opacity={entry.opacity}
  style:transform="scale({entry.scale})"
>
  <svg
    class="canvas"
    width={canvas}
    height={canvas}
    viewBox="{-canvas / 2} {-canvas / 2} {canvas} {canvas}"
    aria-hidden="true"
  >
    {#each ripples(t, radius) as ring, index (index)}
      <path class="ripple" d={ring.path} opacity={ring.opacity} stroke-width={ring.width} />
    {/each}
    {#each droplets as drop, index (index)}
      <ellipse
        class="droplet"
        rx={drop.long}
        ry={drop.wide}
        opacity={drop.opacity}
        style:--tint="{Math.round(drop.tint * 100)}%"
        transform="translate({drop.x} {drop.y}) rotate({drop.rotate})"
      />
    {/each}
    <path class="blob" class:hatched d={blob(t, radius, (angle) => swallowing(t, angle))} />
  </svg>

  <!-- Mounted from the start, unseen, so the emoji is loaded and drawn before
       its moment. Sized by font size rather than scaled, so it stays sharp. -->
  <span
    class="face"
    aria-hidden={!hatched}
    style:font-size="{Math.max(1, markSize * 0.85 * faceNow.scale)}px"
    style:opacity={faceNow.opacity}
    style:transform="rotate({faceNow.rotate}deg)"
  >
    {emoji}
  </span>

  {#if !hatched}
    <span
      class="mark"
      style:width="{markSize}px"
      style:height="{markSize}px"
      style:transform="translate({markNow.x * radius}px, {markNow.y * radius}px) rotate({markNow.rotate}deg)
      scale({markNow.scale})"
    >
      <Icon name="brand/avatar" size="fill" />
    </span>
  {/if}
</div>

<style>
  .hatch {
    position: relative;
    display: grid;
    place-items: center;
    flex: none;
  }

  /* Centred on the hatch and free to spill past it. */
  .canvas {
    position: absolute;
    top: 50%;
    left: 50%;
    translate: -50% -50%;
    overflow: visible;
    pointer-events: none;
  }

  .blob {
    fill: var(--color-surface-impact-base);
    transition: fill 250ms ease-out;
  }

  /* Once the agent has a face, the circle softens to a neutral surface. */
  .blob.hatched {
    fill: var(--color-surface-standard-elevated);
  }

  .droplet {
    fill: color-mix(
      in oklab,
      var(--color-surface-impact-base) var(--tint),
      var(--color-text-standard-muted)
    );
  }

  .ripple {
    fill: none;
    stroke: var(--color-surface-impact-base);
  }

  .mark,
  .face {
    position: relative;
    grid-area: 1 / 1;
  }

  .mark {
    color: var(--color-text-standard-base);
  }

  .face {
    line-height: 1;
  }
</style>
