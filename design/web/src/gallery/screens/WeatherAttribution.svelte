<script lang="ts">
  import WeatherAttributionStatus from "./WeatherAttributionStatus.svelte";
  let { state = "loaded", onRetry = () => {} }: { state?: string; onRetry?: () => void } = $props();
  import AppleWeatherMark from "./AppleWeatherMark.svelte";
</script>

{#if state !== "loaded"}
  <WeatherAttributionStatus {state} {onRetry} />
{:else}
  <a
    class="attribution"
    href="https://weatherkit.apple.com/legal-attribution.html"
    target="_blank"
    rel="noopener noreferrer"
  >
    <AppleWeatherMark />
    <span class="t-note legal">Weather data sources</span>
  </a>
{/if}

<style>
  .attribution {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    align-self: flex-start;
    width: fit-content;
    gap: var(--spacing-n4);
    padding-block: var(--spacing-n8);
    text-decoration: none;
    color: var(--color-text-standard-muted);
  }
  .legal {
    text-decoration: underline;
    text-underline-offset: 0.2em;
  }
</style>
