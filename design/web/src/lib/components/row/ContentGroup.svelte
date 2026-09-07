<script lang="ts">
  import type { Snippet } from "svelte";
  import CardSurface from "../card/CardSurface.svelte";
  import "./row.css";

  interface Props {
    /** Section heading above the card. */
    label?: string;
    /** Small print about this group, bound to the card at the grouping gap. */
    footnote?: string;
    children: Snippet;
  }

  const { label, footnote, children }: Props = $props();
</script>

<!--
  A section of content: an optional label above a card of rows, divided by
  hairlines inset to the row text, and optional small print below it.

  The footnote belongs to the group rather than the page: laid out by hand it
  drifts to the page gap, which is five times wider, and then reads as a
  statement about the whole screen.

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
  {#if footnote}
    <p class="t-note footnote">{footnote}</p>
  {/if}
</section>

<style>
  .group {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }

  .label {
    margin: 0;
    /* On the same column the row text starts at: the label names the rows, so
       it lines up with them rather than with the card's edge. */
    padding: 0 var(--spacing-n24);
    color: var(--color-text-standard-muted);
    text-box: normal;
  }

  .rows {
    display: flex;
    flex-direction: column;
  }

  /* Prose, not a label: `note` is the UI face at regular weight, where `tag`
     is the letterspaced display face the group's own label uses. A footnote
     is a sentence you read, so it is set like one. */
  .footnote {
    margin: 0;
    /* Level with the label above and the row text between them. */
    padding: 0 var(--spacing-n24);
    color: var(--color-text-standard-muted);
  }
</style>
