<script module lang="ts">
  /** The green circle's size inside the ring, for an avatar `size` across.
     Matches `OnboardingAvatar.vesselSize(for:)` on iOS. */
  export function vesselSize(size: number): number {
    return size - Math.max(3, size * 0.045) * 2.4;
  }
</script>

<script lang="ts">
  import { ChasingProgress, Icon, driveFrames } from "@lib";
  import { splinePath } from "@lib/components/morph/figure";
  import { outline } from "@gallery/screens/onboarding/opening";
  import { gentle, spring } from "@gallery/screens/onboarding/spring";

  let {
    progress,
    emoji,
    showsProgress = true,
    animatesIn = true,
    breath = 0,
    stretch = 0,
    size = 96,
  }: {
    /** How far the agent has come together, 0–1. Chased, never snapped. */
    progress: number;
    /** The agent's face. Cross-fades the centre from the brand mark. */
    emoji?: string;
    /** Draws the ring and dims the mark to the fill. Off for the welcome moment. */
    showsProgress?: boolean;
    /** Fades in on appear. Off when it should already be there, like at launch. */
    animatesIn?: boolean;
    /** How far through the opening's breath the green circle is, 0–1. */
    breath?: number;
    /** Pulls the green circle tall (above 0) or wide (below), keeping its area. */
    stretch?: number;
    size?: number;
  } = $props();

  const chaser = new ChasingProgress();
  let fill = $state(0);

  /* The chaser's own clock only runs while frames do, so a new target after
     a long idle travels instead of jumping the whole gap in one tick. */
  let clock = 1;

  $effect(() => {
    chaser.setTarget(progress);
    let previous = 0;
    return driveFrames(
      (now) => {
        clock += previous ? now - previous : 1 / 60;
        previous = now;
        chaser.tick(clock);
        fill = chaser.value;
      },
      () => chaser.isChasing,
    );
  });

  // svelte-ignore state_referenced_locally
  let appeared = $state(!animatesIn);

  $effect(() => {
    const frame = requestAnimationFrame(() => (appeared = true));
    return () => cancelAnimationFrame(frame);
  });

  const landing = spring(0.6, 0.2);

  const ringWidth = $derived(Math.max(3, size * 0.045));
  const radius = $derived((size - ringWidth) / 2);
  const circumference = $derived(2 * Math.PI * radius);
  /* The green circle inside the ring, and the mark at BrandAvatar's proportion. */
  const vessel = $derived(vesselSize(size));
  const markSize = $derived((vessel * (56 - 16)) / 56);
  /* The green circle, breathing through the opening, and the mark it presses. */
  const opening = $derived(outline(breath));
  const blob = $derived(
    splinePath(
      opening.points.map((p) => ({
        x: (1 + p.x / (1 + stretch)) * (vessel / 2),
        y: (1 + p.y * (1 + stretch)) * (vessel / 2),
      })),
    ),
  );

  const markOpacity = $derived(showsProgress ? 0.5 + 0.5 * fill : 1);
  const markSaturation = $derived(showsProgress ? 0.4 + 0.6 * fill : 1);
</script>

<!--
  The agent's presence through onboarding: a ring that fills as the agent
  comes together around the Eigin mark, which blooms into the agent's face.
-->
<div
  class="avatar"
  class:appeared
  style:width="{size}px"
  style:height="{size}px"
  style:--landing-easing={landing.easing}
  style:--landing-ms="{landing.ms}ms"
  style:--gentle-easing={gentle.easing}
  style:--gentle-ms="{gentle.ms}ms"
>
  <svg class="ring" class:shown={showsProgress} viewBox="0 0 {size} {size}" aria-hidden="true">
    <circle class="track" cx={size / 2} cy={size / 2} r={radius} stroke-width={ringWidth} />
    <circle
      class="fill"
      cx={size / 2}
      cy={size / 2}
      r={radius}
      stroke-width={ringWidth}
      stroke-dasharray={circumference}
      stroke-dashoffset={circumference * (1 - fill)}
    />
  </svg>

  <div
    class="vessel"
    class:has-face={emoji}
    style:width="{vessel}px"
    style:height="{vessel}px"
    style:opacity={markOpacity}
    style:filter="saturate({markSaturation})"
  >
    <svg class="blob" viewBox="0 0 {vessel} {vessel}" aria-hidden="true">
      <path d={blob} />
    </svg>
    <span
      class="mark"
      class:hidden={emoji}
      style:width="{markSize}px"
      style:height="{markSize}px"
      style:transform="scale({opening.mark / (1 + stretch / 2)}, {opening.mark *
        (1 + stretch / 2)})"
    >
      <Icon name="brand/avatar" size="fill" />
    </span>
    {#if emoji}
      {#key emoji}
        <span class="face" style:font-size="{markSize * 0.85}px">{emoji}</span>
      {/key}
    {/if}
  </div>
</div>

<style>
  .avatar {
    position: relative;
    display: grid;
    place-items: center;
    flex: none;
    opacity: 0;
    transform: scale(0.85);
  }

  .avatar.appeared {
    opacity: 1;
    transform: none;
    transition:
      transform var(--landing-ms) var(--landing-easing),
      opacity var(--motion-slow) ease-out;
  }

  .ring {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    rotate: -90deg;
    fill: none;
    opacity: 0;
    transition: opacity 500ms ease-out;
  }

  .ring.shown {
    opacity: 1;
  }

  .track {
    stroke: color-mix(in srgb, var(--color-text-standard-muted) 15%, transparent);
  }

  .fill {
    stroke: var(--color-surface-impact-base);
    stroke-linecap: round;
  }

  .vessel {
    position: relative;
    display: grid;
    place-items: center;
    transition:
      opacity 500ms ease-out,
      filter 500ms ease-out;
  }

  /* Drawn from the breath's outline, not a rounded box, so the breath can
     reach past the avatar's edge. */
  .blob {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
    fill: var(--color-surface-impact-base);
    transition: fill var(--gentle-ms) var(--gentle-easing);
  }

  /* Once the agent has a face, the circle softens to a neutral surface. */
  .vessel.has-face .blob {
    fill: var(--color-surface-standard-elevated);
  }

  .mark,
  .face {
    position: relative;
    grid-area: 1 / 1;
  }

  .mark {
    color: var(--color-text-standard-base);
    transition:
      opacity var(--gentle-ms) var(--gentle-easing),
      scale var(--gentle-ms) var(--gentle-easing);
  }

  .mark.hidden {
    opacity: 0;
    scale: 0.6;
  }

  .face {
    line-height: 1;
    animation: bloom var(--gentle-ms) var(--gentle-easing) both;
  }

  @keyframes bloom {
    from {
      opacity: 0;
      scale: 0.6;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .avatar {
      transform: none;
    }
  }
</style>
