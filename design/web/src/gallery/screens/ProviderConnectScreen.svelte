<script lang="ts">
  import ConnectionsScreen from "@gallery/screens/ConnectionsScreen.svelte";
  import ProviderConnectSheet from "@gallery/screens/ProviderConnectSheet.svelte";

  let open = $state(true);
</script>

<!-- The connection step, over the screen it opens from. -->
<div class="host">
  <ConnectionsScreen />
  <ProviderConnectSheet bind:open />
</div>

<style>
  /* The sheet layer anchors to its nearest positioned ancestor, so the phone
     frame confines it rather than the page. */
  .host {
    position: relative;
    height: 100%;
  }
</style>
