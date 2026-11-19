<script lang="ts">
  import CallBrief from "#lib/CallBrief.svelte";
  import type { PageProps } from "./$types";
  let { data }: PageProps = $props();
</script>

{#if data.brief}
  <article class="guide-content" aria-label="Call brief">
    <CallBrief text={data.brief} />
  </article>
{:else}
  <p class="t-standfirst">
    The original call brief is unavailable. Choose a submission to read its
    latest saved revision.
  </p>
{/if}
