<script lang="ts">
  import type { Snippet } from "svelte";
  import SoftEdgeScroll from "@lib/internal/SoftEdgeScroll.svelte";

  const { header, footer, children }: { header?: Snippet; footer?: Snippet; children: Snippet } =
    $props();
</script>

<!--
  The scrolling body of a settings-style screen: groups stacked down the page
  with the page-layout gap, inset by n16, and room to clear the bottom. The
  header and footer float over it, and content softens as it scrolls beneath.

  The stack is at least as tall as the screen, so anything marked `bottom`
  rests on the floor and rides up as the content grows past it.
-->
<SoftEdgeScroll {header} {footer} flushFooter>
  <div class="stack">
    {@render children()}
  </div>
</SoftEdgeScroll>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
    min-height: 100%;
    gap: var(--sizing-pageLayout-gap);
    padding: var(--spacing-n8) var(--spacing-n16) var(--spacing-n32);
  }

  /* Auto margin rather than a spacer element: a spacer is a flex item, so it
     would carry the stack's gap on both sides and leave twice the air above
     the actions once the leftover room ran out. */
  .stack :global(.bottom) {
    margin-top: auto;
  }
</style>
