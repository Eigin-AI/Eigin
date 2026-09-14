<script lang="ts">
  import { MediaQuery } from "svelte/reactivity";
  import { maxFormSize } from "./forms";
  import { figureOf, splinePath } from "./figure";
  import { MorphIntensity } from "./intensity";
  import { ENTRY_DURATION, MorphTimeline } from "./timeline";

  interface Props {
    /** Anchors and seeds the choreography; a new value restarts the entry. */
    shownAt?: number;
    /** How much of the wobble is showing. */
    intensity?: MorphIntensity;
    /**
     * Breathing on its own, for a blob that is present and waiting rather than
     * working. Ramps like `intensity`, so it eases into the wobble instead of
     * cutting out when the agent starts thinking.
     */
    breath?: MorphIntensity;
    /** Time multiplier: below 1 makes big blobs dance less briskly. */
    tempo?: number;
    /** Seconds to hold invisible before the scale-in plays. */
    entryDelay?: number;
    /** Fill colour; defaults to the spot button colour. */
    color?: string;
  }

  const {
    shownAt = performance.now() / 1000,
    intensity = MorphIntensity.full,
    breath = MorphIntensity.none,
    tempo = 1,
    entryDelay = 0,
    color = "var(--color-button-spot-base)",
  }: Props = $props();

  /* Share of the frame the largest form occupies — margin left for the entry
     overshoot and breath. */
  const FILL = 0.875;
  /* Drawn in a fixed viewBox and scaled by CSS, so the blob fills any slot. */
  const VIEW = 100;

  const reduceMotion = new MediaQuery("(prefers-reduced-motion: reduce)");

  const timeline = $derived(new MorphTimeline(Math.round(shownAt * 1000)));

  let now = $state(performance.now() / 1000);

  /* Nothing moves once the entry has played and the wobble is at rest, so the
     loop parks itself rather than redrawing a settled circle every frame.
     Liveliness is judged inside the tick against a fresh clock: reading it
     from `now` would strand the blob, since a parked loop leaves `now` stale
     and a re-engaged intensity would still look settled. */
  $effect(() => {
    // Re-arm whenever the choreography's inputs change.
    void intensity;
    void breath;
    void shownAt;
    void entryDelay;
    void reduceMotion.current;

    let frame = requestAnimationFrame(function tick() {
      const t = performance.now() / 1000;
      now = t;
      const lively =
        !reduceMotion.current &&
        (t - shownAt < entryDelay + ENTRY_DURATION ||
          intensity.value(t) > 0 ||
          breath.value(t) > 0);
      if (lively) frame = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(frame);
  });

  const path = $derived.by(() => {
    const t = now - shownAt;
    const still = reduceMotion.current;
    const pose = still ? { from: 0, to: 0, progress: 0 } : timeline.pose(t * tempo);
    const wobble = still ? 0 : intensity.value(now);
    const figure = figureOf(pose, wobble);

    // The entry overshoot plays on any appearance, after the delay. The breath
    // rides along with the wobble, and can also be asked for on its own — so a
    // waiting blob breathes and a calm one is still.
    const entry = still ? 1 : timeline.entryScale(t - entryDelay);
    const breathing = still ? 0 : Math.max(wobble, breath.value(now));
    const breathScale = still ? 1 : 1 + (timeline.breath(t) - 1) * breathing;

    const scale = (VIEW * FILL) / maxFormSize;
    const halfWidth = (figure.width / 2) * scale * entry * breathScale;
    const halfHeight = (figure.height / 2) * scale * entry * breathScale;
    if (halfWidth <= 0 || halfHeight <= 0) return "";

    const center = VIEW / 2;
    return splinePath(
      figure.points.map((p) => ({
        x: center + p.x * halfWidth,
        y: center + p.y * halfHeight,
      })),
    );
  });
</script>

<svg class="morph-blob" viewBox="0 0 {VIEW} {VIEW}" aria-hidden="true">
  <path d={path} fill={color} />
</svg>

<style>
  .morph-blob {
    display: block;
    width: 100%;
    height: 100%;
    overflow: visible;
  }
</style>
