<script lang="ts">
  import type { Anchor, Size } from "@gallery/showcase/shots";

  let {
    text,
    at,
    size,
    ink,
    scale,
  }: { text: string; at: Anchor; size: Size; ink: string; scale: number } = $props();

  const [edge, side] = $derived(at.split("-") as [string, string]);
  /* One margin on every side, from the short edge, so the gap to the side
     matches the gap to the top or bottom. */
  const margin = $derived(Math.min(size.width, size.height) * 0.09);
  const fontSize = $derived(Math.min(size.width * 0.055, size.height * 0.085) * scale);
  /* Returns in the text are the line breaks; without them it wraps itself. */
  const broken = $derived(text.includes("\n"));
</script>

<!-- Pinned to the canvas, not the layout, so moving the phone never moves it. -->
<div class="headline-area edge-{edge} side-{side}" style:inset="{margin}px">
  <h1 class="headline" class:broken style:color={ink} style:font-size="{fontSize}px">{text}</h1>
</div>

<style>
  .headline-area {
    position: absolute;
    display: flex;
    pointer-events: none;
    z-index: 1;
  }

  .edge-top {
    align-items: flex-start;
  }

  .edge-center {
    align-items: center;
  }

  .edge-bottom {
    align-items: flex-end;
  }

  .side-left {
    justify-content: flex-start;
    text-align: left;
  }

  .side-center {
    justify-content: center;
    text-align: center;
  }

  .side-right {
    justify-content: flex-end;
    text-align: right;
  }

  .headline {
    margin: 0;
    max-width: 11ch;
    font-family: var(--font-display);
    font-weight: 700;
    font-feature-settings: "ss01" 1;
    line-height: 1.04;
    letter-spacing: -0.01em;
    text-transform: uppercase;
    text-wrap: balance;
    /* Trims the line box to the capitals, so the margin is measured to the letters. */
    text-box: trim-both cap alphabetic;
  }

  /* Centred over the phone, a headline can run the width of the canvas. */
  .side-center > .headline {
    max-width: none;
  }

  .headline.broken {
    max-width: none;
    white-space: pre;
  }
</style>
