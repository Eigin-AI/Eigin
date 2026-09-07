<script lang="ts">
  import ConnectionsScreen from "@gallery/screens/ConnectionsScreen.svelte";
  import ConnectIntegrationSheet from "@gallery/screens/ConnectIntegrationSheet.svelte";

  let open = $state(true);
</script>

<!-- The connection step, over the screen it opens from. -->
<div class="host">
  <ConnectionsScreen />
  <ConnectIntegrationSheet bind:open />
</div>

<style>
  .host {
    position: relative;
    height: 100%;
  }
</style>
