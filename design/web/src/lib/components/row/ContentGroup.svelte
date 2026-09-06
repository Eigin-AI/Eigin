<script lang="ts">
  import type { Snippet } from "svelte";
  import CardSurface from "../card/CardSurface.svelte";
  import "./row.css";

  interface Props {
    /** Section heading above the card. */
    label?: string;
    children: Snippet;
  }

  const { label, children }: Props = $props();
</script>

<!--
  A section of content: an optional label above a card of rows, divided by
  hairlines inset to the row text.

  Web-first: iOS assembles this from a copied section-label function, a
  zero-padding card surface and a tight stack on every settings screen.
-->
<section class="group">
  {#if label}
    <h3 class="t-miniLabel label">{label}</h3>
  {/if}
  <CardSurface padding={0}>
    <div class="rows eigin-rows">
      {@render children()}
    </div>
  </CardSurface>
</section>

<style>
  .group {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }

  .label {
    margin: 0;
    /* Clear of the card's rounded corner, not aligned to the row text. */
    padding: 0 var(--spacing-n8);
    color: var(--color-text-standard-muted);
    text-box: normal;
  }

  .rows {
    display: flex;
    flex-direction: column;
  }
</style>
