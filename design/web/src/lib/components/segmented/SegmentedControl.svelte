<script lang="ts">
  import type { Segment } from "./types";

  let {
    segments,
    selection,
    disabled = false,
    onSelect,
  }: {
    segments: Segment[];
    /** Currently selected segment value. */
    selection: string;
    disabled?: boolean;
    onSelect?: (value: string) => void;
  } = $props();

  /* Falls back to the first segment so the indicator always has a home. */
  const selectedIndex = $derived(
    Math.max(
      segments.findIndex((segment) => segment.value === selection),
      0,
    ),
  );

  let track = $state<HTMLDivElement>();
  let thumb = $state({ left: 0, width: 0 });

  /* Measured rather than divided into equal shares: a long label widens its
     column, and an indicator sized by segment count then sits off its word. */
  function measure() {
    const segment = track?.querySelectorAll<HTMLElement>(".segment")[selectedIndex];
    if (!segment || !track) return;
    thumb = { left: segment.offsetLeft, width: segment.offsetWidth };
  }

  $effect(() => {
    /* Re-measure when the selection moves or the segments themselves change. */
    void selectedIndex;
    void segments.length;
    measure();
    if (!track) return;
    const observer = new ResizeObserver(measure);
    observer.observe(track);
    for (const segment of track.querySelectorAll(".segment")) observer.observe(segment);
    return () => observer.disconnect();
  });
</script>

<!--
  A pill track with a sliding indicator that
  glides to the tapped segment. Reflects `selection` and reports back through
  `onSelect`, leaving state with the caller.
-->
<div
  class="track"
  class:disabled
  role="radiogroup"
  style:--segments={segments.length}
  bind:this={track}
>
  <span class="indicator" style:transform="translateX({thumb.left}px)" style:width="{thumb.width}px"
  ></span>
  {#each segments as segment (segment.value)}
    <button
      type="button"
      role="radio"
      aria-checked={segment.value === selection}
      class="segment t-navTab"
      class:selected={segment.value === selection}
      {disabled}
      onclick={() => onSelect?.(segment.value)}
    >
      {segment.label}
    </button>
  {/each}
</div>

<style>
  .track {
    position: relative;
    display: grid;
    /* Segments share the track through 1fr columns; the indicator itself is
       measured from the laid-out segments, so labels of different widths
       still land it right. */
    grid-template-columns: repeat(var(--segments), 1fr);
    box-sizing: border-box;
    height: var(--sizing-segmentedControl-track-height);
    /* Indicator inset of n4 around the track. */
    padding: var(--spacing-n4);
    border-radius: var(--radius-full);
    background: var(--color-input-standard-inactive);
  }

  .track.disabled {
    opacity: 0.5;
  }

  .indicator {
    position: absolute;
    top: var(--spacing-n4);
    bottom: var(--spacing-n4);
    left: 0;
    border-radius: var(--radius-full);
    background: var(--color-interaction-active-fill);
    transition:
      transform var(--motion-fast) var(--motion-easing-snap),
      width var(--motion-fast) var(--motion-easing-snap);
  }

  .segment {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    border-radius: var(--radius-full);
    color: var(--color-text-standard-muted);
    font-family: inherit;
    cursor: pointer;
    transition: color var(--motion-fast) var(--motion-easing-snap);
    padding: 0 var(--spacing-n16);
    white-space: nowrap;
  }

  .segment.selected {
    color: var(--color-text-button-onSpot);
  }

  .segment:disabled {
    cursor: default;
  }
</style>
