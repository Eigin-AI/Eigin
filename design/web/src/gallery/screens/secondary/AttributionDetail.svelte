<script lang="ts">
  import type { Snippet } from "svelte";
  let {
    heading,
    provenance,
    mark,
    children,
  }: {
    heading?: string;
    provenance: string;
    mark?: Snippet;
    children: Snippet;
  } = $props();
</script>

<div class="detail">
  <div class="identity">
    {#if mark}<div class="provider-mark">{@render mark()}</div>{/if}
    {#if heading}<p class="t-titleXS">{heading}</p>{/if}
    <p class="t-tag provenance">{provenance}</p>
  </div>
  <div class="detail-content">{@render children()}</div>
</div>

<style>
  .detail {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-headerGrouping-gap);
  }
  .identity {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n8);
    padding-inline: var(--spacing-n24);
  }
  .identity p {
    margin: 0;
  }
  .provider-mark {
    padding-bottom: var(--spacing-n8);
  }
  .provenance {
    color: var(--color-text-standard-muted);
  }
  .detail-content {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }
</style>
