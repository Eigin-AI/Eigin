<script lang="ts">
  let {
    size = 32,
    stroke = 4,
  }: {
    /** Outer diameter in px. */
    size?: number;
    stroke?: number;
  } = $props();

  const radius = $derived((size - stroke) / 2);
  const circumference = $derived(2 * Math.PI * radius);
</script>

<!--
  Waiting, with nothing to count.

  The asset row's ring, for work with no fraction to report: a track, and a
  short arc drifting round it. Running, without guessing how far along.
-->
<svg viewBox="0 0 {size} {size}" width={size} height={size} aria-hidden="true">
  <circle
    cx={size / 2}
    cy={size / 2}
    r={radius}
    fill="none"
    stroke="var(--color-border-standard-base)"
    stroke-width={stroke}
  />
  <circle
    class="sweep"
    cx={size / 2}
    cy={size / 2}
    r={radius}
    fill="none"
    stroke="var(--color-accent)"
    stroke-width={stroke}
    stroke-linecap="round"
    stroke-dasharray="{circumference * 0.18} {circumference}"
  />
</svg>

<style>
  svg {
    display: block;
    flex: none;
  }

  .sweep {
    transform-origin: center;
    animation: eigin-sweep 1.6s linear infinite;
  }

  @keyframes eigin-sweep {
    to {
      transform: rotate(360deg);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .sweep {
      animation: none;
    }
  }
</style>
