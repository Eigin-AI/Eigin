<script lang="ts">
  import type { Snippet } from "svelte";
  import DataRows from "./DataRows.svelte";
  import type { Json } from "./types";

  const {
    value,
    label,
    footnote,
    align = "justified",
    openDepth = 0,
    preview = 5,
    limit = 280,
  }: {
    /** The document to read out. Any JSON shape.  */
    value: Json;
    /** Section heading above the card. */
    label?: string;
    /** Small print about what is in the card, bound to it at the grouping gap. */
    footnote?: Snippet;
    /** Whatever belongs under the card: a footnote, an action, both. */
    align?: "inline" | "justified";
    /** How many levels stand open before anything is touched. None, by default. */
    openDepth?: number;
    /** How many rows of a long list are shown before it offers the rest. */
    preview?: number;
    /** How many characters of a long value are shown before it offers the rest. */
    limit?: number;
  } = $props();
</script>

<!--
  Semi-structured data, read as facts rather than as syntax — a tool's
  arguments, an error payload, whatever a service handed back, usually arriving
  as JSON.

  A table is for data that is already a grid. This is for data that is not:
  labels on the left, values at the opposite edge, and structure shown by what
  it is rather than by punctuation. Nesting folds, a set of values becomes one
  row, and a list of matching records becomes a table after all. Nothing is
  dropped, so this can stand in place of showing the raw document.

  It shares the elevated surface with tables and code blocks, being the same
  class of thing: a payload quoted inside a screen, not part of the screen's
  own prose.
-->
<section class="data">
  {#if label}
    <h3 class="t-miniLabel label">{label}</h3>
  {/if}

  <div class="card">
    <DataRows {value} {align} {openDepth} {preview} {limit} />
  </div>

  {#if footnote}
    <div class="tail">
      {@render footnote()}
    </div>
  {/if}
</section>

<style>
  .data {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }

  .label {
    margin: 0;
    /* On the column the card's own labels start at. */
    padding: 0 var(--spacing-n20);
    color: var(--color-text-standard-muted);
    text-box: normal;
  }

  /* The surface a table or a code block sits on: quoted data, not prose. */
  .card {
    box-sizing: border-box;
    width: 100%;
    padding: var(--spacing-n20);
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-elevated);
  }

  /*
   * The footnote's line: leading edge, quiet, level with the card's own
   * labels — a content group's footnote, with whatever the caller put in it.
   * Colour and placement are set here; the type is the caller's, since a line
   * of prose and a small action are not set the same way.
   */
  .tail {
    display: flex;
    align-items: center;
    gap: var(--spacing-n8);
    padding: 0 var(--spacing-n20);
    color: var(--color-text-standard-muted);
  }
</style>
