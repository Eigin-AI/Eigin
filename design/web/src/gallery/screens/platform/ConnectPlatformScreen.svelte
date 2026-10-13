<script lang="ts">
  import ConnectionsScreen from "@gallery/screens/ConnectionsScreen.svelte";
  import ConnectPlatformSheet from "@gallery/screens/platform/ConnectPlatformSheet.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import {
    platformIntegrations,
    type ConnectPlatformStep,
  } from "@gallery/screens/platform/platformIntegrations";

  const steps = ["disclosure", "asking", "refused", "done"] as const;
  let open = $state(true);
  let id = $state("health");
  let step = $state<ConnectPlatformStep>("disclosure");

  useStageControls(() => controls);
</script>

{#snippet controls()}
  <OptionSelector options={platformIntegrations.map((entry) => entry.id)} bind:value={id} />
  <OptionSelector options={steps} bind:value={step} />
{/snippet}

<!-- Connecting from the catalogue, over the screen it opens from. -->
<div class="host">
  <ConnectionsScreen />
  <ConnectPlatformSheet bind:open bind:step {id} />
</div>

<style>
  .host {
    position: relative;
    height: 100%;
  }
</style>
