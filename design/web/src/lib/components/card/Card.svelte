<script lang="ts">
  import type { Snippet } from "svelte";
  import type { CardSize } from "./types";
  import { overflowFade } from "../../internal/overflowFade";

  let {
    headline,
    explainer,
    size = "large",
    image,
    width,
    height,
    action,
  }: {
    headline: string;
    explainer: string;
    size?: CardSize;
    /** Media content; large puts it on top, small beside the text. */
    image?: Snippet;
    /** Content width in px; omit for the size's default. `"fill"` stretches. */
    width?: number | "fill";
    /** Content height in px; omit for the size's default. */
    height?: number;
    action?: () => void;
  } = $props();

  /* These size the card *content*, with the card's own padding sitting
     outside — width and height exclude the padding, like a frame. */
  const defaultSize: Record<CardSize, { width: number; height: number | null }> = {
    large: { width: 280, height: 330 },
    small: { width: 350, height: 150 },
    compact: { width: 280, height: null },
  };

  const style = $derived.by(() => {
    const fallback = defaultSize[size];
    const w = width === "fill" ? "100%" : `${width ?? fallback.width}px`;
    const h = height ?? fallback.height;
    return `width:${w}` + (h !== null ? `;height:${h}px` : "");
  });

  const tag = $derived(action ? "button" : "div");
</script>

<!--
  Fixed headline/explainer/image layouts in three sizes.
  Text that doesn't fit scrolls under a fade mask (the ViewThatFits fallback).
-->
{#snippet body()}
  {#if size === "large"}
    <div class="media">{@render image?.()}</div>
    <div class="scroller" use:overflowFade>
      <div class="text large">
        <span class="t-titleS">{headline}</span>
        <span class="t-description">{explainer}</span>
      </div>
    </div>
  {:else if size === "small"}
    <div class="scroller" use:overflowFade>
      <div class="text small">
        <span class="t-titleS">{headline}</span>
        <span class="t-description">{explainer}</span>
      </div>
    </div>
    <div class="media thumb">{@render image?.()}</div>
  {:else}
    <div class="text compact">
      <span class="t-titleXS">{headline}</span>
      <span class="t-description">{explainer}</span>
    </div>
  {/if}
{/snippet}

<svelte:element
  this={tag}
  class="card {size}"
  class:tappable={action}
  class:fill={width === "fill"}
  {style}
  onclick={action}
  type={action ? "button" : undefined}
  role={action ? "button" : undefined}
>
  {@render body()}
</svelte:element>

<style>
  /* content-box: width and height size the content, padding excluded. */
  .card {
    position: relative;
    box-sizing: content-box;
    display: flex;
    flex-direction: column;
    background: var(--color-surface-standard-elevated);
    border-radius: var(--radius-card);
    border: none;
    text-align: left;
    font-family: inherit;
    flex: none;
    padding: 0;
  }

  /* Filling means filling the box it is in, padding included — content-box
     sizing would push the card past its column by its own padding. */
  .card.fill {
    box-sizing: border-box;
  }

  /* Hover / pressed overlay for tappable cards. */
  .card.tappable {
    cursor: pointer;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .card.tappable::after {
    content: "";
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background: var(--color-interaction-light-hover);
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
    pointer-events: none;
  }

  .card.tappable:hover::after {
    opacity: 1;
  }

  /* A tap fades the card toward the surface behind rather than washing it:
     a dark wash both darkened and cooled a warm card. */
  .card.tappable:active {
    opacity: 0.75;
    transition: opacity var(--motion-fast) var(--motion-easing-snap);
  }

  /* --- Large: image on top, text below ----------------------------------- */

  .card.large {
    padding: var(--sizing-card-py-top) var(--sizing-card-px-small) 0;
  }

  .card.large .media {
    height: 180px;
    /* Concentric with the card: outer radius minus the 8px inset. */
    border-radius: calc(var(--radius-card) - var(--sizing-card-px-small));
    overflow: hidden;
    flex: none;
  }

  .text.large {
    padding: var(--sizing-card-gap-imageText) var(--sizing-card-gap-text)
      var(--sizing-card-py-bottom);
  }

  /* --- Small: text beside a square image --------------------------------- */

  .card.small {
    flex-direction: row;
    align-items: stretch;
    column-gap: var(--sizing-card-gap-text);
    overflow: hidden;
  }

  .card.small .scroller {
    flex: 1;
    justify-content: center;
  }

  .text.small {
    padding: var(--sizing-card-py-small) 0 var(--sizing-card-py-small) var(--sizing-card-px-large);
  }

  .card.small .media.thumb {
    width: 100px;
    margin: var(--sizing-card-px-small) var(--sizing-card-px-small) var(--sizing-card-px-small) 0;
    /* Concentric with the card: outer radius minus the 8px inset. */
    border-radius: calc(var(--radius-card) - var(--sizing-card-px-small));
    overflow: hidden;
    flex: none;
  }

  /* --- Compact: text only -------------------------------------------------- */

  .card.compact {
    padding: var(--sizing-card-py-compact)
      calc(var(--sizing-card-gap-text) + var(--sizing-card-px-small));
    justify-content: center;
  }

  /* --- Text --------------------------------------------------------------- */

  .text {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    /* Real token gap: typography is cap-to-baseline trimmed, so no fudge. */
    gap: var(--sizing-card-gap-text);
  }

  .text.compact {
    gap: var(--sizing-card-gap-textCompact);
  }

  .card span {
    color: var(--color-text-standard-base);
  }

  /* Trimmed text boxes end at cap and baseline, so ascenders/descenders spill
     outside them. Only clip once the content actually scrolls. */
  .scroller {
    display: flex;
    flex-direction: column;
    min-height: 0;
    overflow: visible;
  }

  .scroller:global(.is-scrollable) {
    overflow-y: auto;
    scrollbar-width: none;
    mask-image: linear-gradient(to bottom, transparent 0, #000 5%, #000 80%, transparent 100%);
  }

  .card :global(.media > *) {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
</style>
