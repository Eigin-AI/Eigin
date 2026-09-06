<script lang="ts">
  import Icon from "../icon/Icon.svelte";
  import type { IconName } from "../../generated/icons";
  import type { VisualCardVariant } from "./types";
  import { overflowFade } from "../../internal/overflowFade";

  let {
    headline,
    explainer,
    symbol,
    variant = "brand",
    action,
  }: {
    headline: string;
    explainer: string;
    symbol: IconName;
    /** Mirrors `AppVisualCardVariant`. */
    variant?: VisualCardVariant;
    action?: () => void;
  } = $props();

  const tag = $derived(action ? "button" : "div");
</script>

<!--
  300×360 impact card with a large symbol above the
  text. Every variant uses the onPrimary foreground, as on iOS.
-->
<svelte:element
  this={tag}
  class="visual {variant}"
  class:tappable={action}
  onclick={action}
  type={action ? "button" : undefined}
  role={action ? "button" : undefined}
>
  <Icon name={symbol} size={110} />
  <div class="text" use:overflowFade>
    <span class="t-titleL">{headline}</span>
    <span class="t-description">{explainer}</span>
  </div>
</svelte:element>

<style>
  .visual {
    position: relative;
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    /* No less than n24 between symbol and text. */
    gap: var(--spacing-n24);
    width: 300px;
    height: 360px;
    padding: var(--spacing-n40) var(--spacing-n24);
    border-radius: var(--radius-card);
    border: none;
    font-family: inherit;
    color: var(--color-text-button-onPrimary);
    text-align: left;
    flex: none;
    overflow: hidden;
  }

  .visual.tappable {
    cursor: pointer;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .visual.tappable::after {
    content: "";
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background: var(--color-interaction-light-hover);
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
    pointer-events: none;
  }

  .visual.tappable:hover::after {
    opacity: 1;
  }

  /* A tap fades the card toward the surface behind rather than washing it:
     a dark wash both darkened and cooled a warm card. */
  .visual.tappable:active {
    opacity: 0.75;
    transition: opacity var(--motion-fast) var(--motion-easing-snap);
  }

  .visual.brand {
    background: var(--color-surface-impact-base);
  }

  .visual.warm {
    background: var(--color-surface-impact-alternative);
  }

  .visual.soft {
    background: var(--color-surface-impact-subtle);
  }

  .visual.neutral {
    background: var(--color-surface-standard-elevated);
  }

  /* Symbol inherits the card foreground through currentColor. */
  .visual :global(svg) {
    color: inherit;
    flex: none;
  }

  .text {
    display: flex;
    flex-direction: column;
    /* Real token gap: typography is cap-to-baseline trimmed, so no fudge. */
    gap: var(--sizing-card-gap-text);
    /* A spacer pins the text to the bottom of the card. */
    margin-top: auto;
    min-height: 0;
    /* Trimmed boxes end at cap/baseline; don't clip the glyph overhang. */
    overflow: visible;
  }

  .text:global(.is-scrollable) {
    overflow-y: auto;
    scrollbar-width: none;
    mask-image: linear-gradient(to bottom, transparent 0, #000 5%, #000 80%, transparent 100%);
  }
</style>
