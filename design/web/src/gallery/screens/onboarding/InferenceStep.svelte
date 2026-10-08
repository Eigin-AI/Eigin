<script lang="ts">
  import { AssetRow, Button, Sheet } from "@lib";
  import type { AssetState } from "@lib";
  import GetCreditsSheet from "@gallery/screens/GetCreditsSheet.svelte";
  import ProviderSelectSheet from "@gallery/screens/ProviderSelectSheet.svelte";

  let {
    hasCredits,
    onUseCloud,
  }: {
    /** With credits, Eigin proceeds at once; without, it asks you to buy some. */
    hasCredits: boolean;
    onUseCloud: () => void;
  } = $props();

  let showCredits = $state(false);
  let showOffline = $state(false);
  let showProviders = $state(false);
  let download = $state<AssetState>({ kind: "notDownloaded" });

  const downloading = $derived(download.kind !== "notDownloaded");

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
  {#if !downloading}
    <button class="link t-navTab" type="button" onclick={() => (showOffline = true)}>
      Set up an offline model
    </button>
  {/if}

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

<!-- Layout never moves: the copy and the button swap in place once the
     download starts. -->
<Sheet bind:open={showOffline} title="Use Eigin offline">
  {#snippet primary()}
    <div class="offline">
      <AssetRow name="Gemma 4 E2B" state={download} sizeDescription="~2.6 GB" showsAction={false} />
      <p class="t-description pitch">
        {downloading
          ? "Downloading now. It’ll be ready a bit later. For now, pick how you want to run this first conversation."
          : "Run a model on your device, with no internet and nothing leaving your phone. It downloads in the background while you get started, and you can start using it once it’s ready."}
      </p>
      {#if downloading}
        <Button label="Continue" onclick={() => (showOffline = false)} />
      {:else}
        <Button
          label="Download"
          onclick={() =>
            (download = {
              kind: "downloading",
              fractionCompleted: 0.08,
              estimatedSecondsLeft: 540,
            })}
        />
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
