<script lang="ts">
  import { AssetRow, Button, Sheet } from "@lib";
  import type { AssetState } from "@lib";
  import GetCreditsSheet from "@gallery/screens/GetCreditsSheet.svelte";
  import ProviderSelectSheet from "@gallery/screens/ProviderSelectSheet.svelte";
  import {
    downloadStates,
    hardwareGuidance,
    unsupportedDescription,
    type DownloadStage,
  } from "@gallery/screens/localModel";

  let {
    hasCredits,
    onUseCloud,
    isSupported,
    downloadStage = $bindable<DownloadStage>("not installed"),
  }: {
    /** With credits, Eigin proceeds at once; without, it asks you to buy some. */
    hasCredits: boolean;
    onUseCloud: () => void;
    isSupported: boolean;
    downloadStage?: DownloadStage;
  } = $props();

  let showCredits = $state(false);
  let showOffline = $state(false);
  let showProviders = $state(false);
  const download = $derived<AssetState>(downloadStates[downloadStage]);
  const offersAction = $derived(
    isSupported && ["notDownloaded", "failed", "unavailable"].includes(download.kind),
  );

  function useEigin() {
    if (hasCredits) onUseCloud();
    else showCredits = true;
  }
</script>

<!--
  Gives the agent a brain. Eigin's cloud is the default, your own provider is
  second, and the offline model is a quiet link: it downloads in the
  background, while the cloud carries this first conversation.
-->
<div class="actions">
  <button class="link t-navTab" type="button" onclick={() => (showOffline = true)}>
    Use Eigin offline
  </button>

  <div class="group">
    <Button label="Use Eigin" onclick={useEigin} />
    <Button
      label="Connect your own provider"
      variant="secondary"
      onclick={() => (showProviders = true)}
    />
  </div>
</div>

<GetCreditsSheet
  bind:open={showCredits}
  onPurchase={() => {
    showCredits = false;
    onUseCloud();
  }}
/>

<ProviderSelectSheet bind:open={showProviders} />

<Sheet
  bind:open={showOffline}
  title="Use Eigin offline"
  description={isSupported
    ? "You can download a local model to use Eigin offline."
    : unsupportedDescription}
>
  {#snippet primary()}
    <div class="offline">
      {#if isSupported}
        <AssetRow
          name="Gemma 4 E2B"
          state={download}
          sizeDescription="~2.6 GB"
          showsAction={false}
        />
      {/if}
      <p class="t-description pitch">
        {isSupported
          ? "It downloads in the background while you get started. After onboarding, you can switch to the local model once it’s ready."
          : hardwareGuidance}
      </p>
      {#if offersAction}
        <Button
          label={download.kind === "notDownloaded" ? "Download" : "Retry"}
          onclick={() => (downloadStage = "downloading")}
        />
      {:else}
        <Button label="Continue" onclick={() => (showOffline = false)} />
      {/if}
    </div>
  {/snippet}
</Sheet>

<style>
  .actions {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n16);
    margin-top: auto;
  }

  .group {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
    align-self: stretch;
  }

  .link {
    padding: 0;
    border: none;
    background: none;
    color: var(--color-text-standard-link);
    cursor: pointer;
  }

  .offline {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n24);
    padding: 0 var(--spacing-n24);
  }

  .pitch {
    margin: 0;
    color: var(--color-text-standard-muted);
  }
</style>
