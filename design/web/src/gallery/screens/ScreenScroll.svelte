<script lang="ts">
  import type { Snippet } from "svelte";

  const { children }: { children: Snippet } = $props();
</script>

<!--
  The scrolling body of a settings-style screen: groups stacked down the page
  with the page-layout gap, inset by n16, and room to clear the bottom.
-->
<div class="scroll">
  <div class="stack">
    {@render children()}
  </div>
</div>

<style>
  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
  }

  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: var(--spacing-n8) var(--spacing-n16) var(--spacing-n32);
  }
</style>
