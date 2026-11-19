<script lang="ts">
  import Disclosure from "@eigin/website/Disclosure.svelte";
  import Preview from "./Preview.svelte";
  import { foldoutParts } from "./foldouts.ts";
  let { text, class: className = "" }: { text: string; class?: string } =
    $props();
  const parts = $derived(foldoutParts(text));
</script>

<div class="foldout-guide">
  {#each parts as part}
    {#if part.kind === "copy"}
      <div class="guide-copy"><Preview text={part.body} /></div>
    {:else}
      {#if part.introduction.trim()}<Preview text={part.introduction} />{/if}
      <div class={className}>
        {#each part.items as item}
          <Disclosure summary={item.title}
            ><Preview text={item.body} /></Disclosure
          >
        {/each}
      </div>
    {/if}
  {/each}
</div>

<style>
  .guide-copy {
    margin-block: var(--spacing-n32);
  }
  .guide-copy:first-child {
    margin-top: 0;
  }
  .guide-copy:last-child {
    margin-bottom: 0;
  }
  .foldout-guide :global(details:last-of-type) {
    border-bottom: 1px solid var(--color-border-standard-base);
  }
</style>
