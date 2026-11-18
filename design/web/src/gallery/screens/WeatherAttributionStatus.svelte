<script lang="ts">
  import { SweepRing } from "@lib";
  let { state, onRetry }: { state: string; onRetry: () => void } = $props();
</script>

{#if state === "loading"}
  <div class="loading t-note" role="status">
    <SweepRing size={24} />
    <span>Loading Apple Weather attribution…</span>
  </div>
{:else}
  <div class="unavailable">
    <p class="t-note" role="status">Apple Weather attribution is unavailable.</p>
    <button class="retry t-note" onclick={onRetry}>Retry</button>
  </div>
{/if}

<style>
  .loading {
    display: flex;
    align-items: center;
    gap: var(--spacing-n12);
  }
  .unavailable {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n8);
  }
  p {
    margin: 0;
  }
  .retry {
    min-height: var(--sizing-button-height-small);
    padding: 0;
    border: 0;
    background: none;
    color: var(--color-text-standard-base);
    cursor: pointer;
    text-decoration: underline;
    text-underline-offset: 0.2em;
  }
</style>
