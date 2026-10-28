<script lang="ts">
  import { untrack } from "svelte";
  import { MediaQuery } from "svelte/reactivity";
  import { maxFormSize } from "./forms";
  import { figureOf, splinePath } from "./figure";
  import { MorphIntensity } from "./intensity";
  import { ENTRY_DURATION, BREATH_PERIOD, BREATH_SCALE_AMPLITUDE, MorphTimeline } from "./timeline";

  interface Props {
    /** Anchors and seeds the choreography; a new value restarts the entry. */
    shownAt?: number;
    /** Freeze the current pose and breathing phase until playback resumes. */
    paused?: boolean;
    /** How much of the wobble is showing. */
    intensity?: MorphIntensity;
    /** Maximum wobble amplitude, from zero to one. */
    intensityScale?: number;
    /**
     * Breathing on its own, for a blob that is present and waiting rather than
     * working. Ramps like `intensity`, so it eases into the wobble instead of
     * cutting out when the agent starts thinking.
     */
    breath?: MorphIntensity;
    /** Time multiplier: below 1 makes big blobs dance less briskly. */
    tempo?: number;
    /** Whether to scale in on first appearance. */
    animateEntry?: boolean;
    /** Seconds to hold invisible before the scale-in plays. */
    entryDelay?: number;
    /** How far the breath swells, as a fraction of the blob's size. */
    breathPulse?: number;
    /** How long one breath cycle takes. */
    breathPeriod?: number;
    /** Fill colour; defaults to the spot button colour. */
    color?: string;
  }

  const {
    shownAt = performance.now() / 1000,
    paused = false,
    intensity = MorphIntensity.full,
    intensityScale = 1,
    breath = MorphIntensity.none,
    tempo = 1,
    animateEntry = true,
    entryDelay = 0,
    breathPulse = BREATH_SCALE_AMPLITUDE,
    breathPeriod = BREATH_PERIOD,
    color = "var(--color-button-spot-base)",
  }: Props = $props();

  /* Share of the frame the largest form occupies — margin left for the entry
     overshoot and breath. */
  const FILL = 0.875;
  /* Drawn in a fixed viewBox and scaled by CSS, so the blob fills any slot. */
  const VIEW = 100;

  const reduceMotion = new MediaQuery("(prefers-reduced-motion: reduce)");

  const timeline = $derived(
    new MorphTimeline(Math.round(shownAt * 1000), {
      breathScaleAmplitude: breathPulse,
      breathPeriod,
    }),
  );

  let now = $state(performance.now() / 1000);
  let pausedFor = $state(0);
  let pausedAt: number | undefined;
  let anchor = untrack(() => shownAt);

  $effect.pre(() => {
    const stopped = paused;
    const start = shownAt;
    untrack(() => {
      const time = performance.now() / 1000;
      if (start !== anchor) {
        pausedFor = 0;
        pausedAt = undefined;
        anchor = start;
      }
      if (stopped) {
        pausedAt ??= time;
      } else if (pausedAt !== undefined) {
        pausedFor += time - pausedAt;
        pausedAt = undefined;
      }
      // Advance the wall clock and its pause offset together, preserving the held pose.
      now = time;
    });
  });

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
    void animateEntry;
    void reduceMotion.current;
    if (paused) return;

    let frame = requestAnimationFrame(function tick() {
      const t = performance.now() / 1000;
      now = t;
      const lively =
        !reduceMotion.current &&
        ((animateEntry && t - shownAt - pausedFor < entryDelay + ENTRY_DURATION) ||
          intensity.value(t) > 0 ||
          breath.value(t) > 0);
      if (lively) frame = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(frame);
  });

  const path = $derived.by(() => {
    const t = now - shownAt - pausedFor;
    const still = reduceMotion.current;
    const pose = still ? { from: 0, to: 0, progress: 0 } : timeline.pose(t * tempo);
    const wobble = still ? 0 : intensity.value(now) * Math.min(1, Math.max(0, intensityScale));
    const figure = figureOf(pose, wobble);

    // The entry overshoot plays on any appearance, after the delay. The breath
    // rides along with the wobble, and can also be asked for on its own — so a
    // waiting blob breathes and a calm one is still.
    const entry = still || !animateEntry ? 1 : timeline.entryScale(t - entryDelay);
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
