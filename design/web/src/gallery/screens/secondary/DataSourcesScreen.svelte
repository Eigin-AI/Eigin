<script lang="ts">
  import { CardSurface, ContentGroup, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import AttributionDetail from "./AttributionDetail.svelte";
  import AppleWeatherMark from "../AppleWeatherMark.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "../stageControls.svelte";
  import WeatherAttributionStatus from "../WeatherAttributionStatus.svelte";
  let weather = $state(false);
  let attributionState = $state("loaded");
  useStageControls(() => (weather ? attributionControls : undefined));
</script>

{#snippet attributionControls()}
  <OptionSelector options={["loaded", "loading", "unavailable"]} bind:value={attributionState} />
{/snippet}

{#if weather}
  <SecondaryScreen title="Apple Weather" onBack={() => (weather = false)}>
    {#if attributionState !== "loaded"}
      <WeatherAttributionStatus
        state={attributionState}
        onRetry={() => (attributionState = "loaded")}
      />
    {:else}
      <AttributionDetail provenance="Provided by Apple · WeatherKit">
        {#snippet mark()}<AppleWeatherMark />{/snippet}
        <CardSurface>
          <div class="disclosure">
            <p class="t-tag">
              Your agent uses Apple Weather for current conditions, hourly forecasts and daily
              forecasts.
            </p>
            <p class="t-tag">
              Apple Weather includes data from other providers. Their attribution and copyright
              information are available on Apple's legal source page.
            </p>
          </div>
        </CardSurface>
        <ContentGroup>
          <Row
            title="Weather data sources"
            description="Attribution and copyright information"
            accessory="link"
            onclick={() =>
              window.open(
                "https://weatherkit.apple.com/legal-attribution.html",
                "_blank",
                "noopener,noreferrer",
              )}
          />
        </ContentGroup>
      </AttributionDetail>
    {/if}
  </SecondaryScreen>
{:else}
  <SecondaryScreen title="Data sources" back="about">
    <ContentGroup>
      <Row
        title="Apple Weather"
        description="Weather conditions and forecasts"
        onclick={() => (weather = true)}
      />
    </ContentGroup>
  </SecondaryScreen>
{/if}

<style>
  .disclosure {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
  }
  .disclosure p {
    margin: 0;
  }
</style>
