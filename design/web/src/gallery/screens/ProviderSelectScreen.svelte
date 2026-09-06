<script lang="ts">
  import ConnectionsScreen from "@gallery/screens/ConnectionsScreen.svelte";
  import ProviderSelectSheet from "@gallery/screens/ProviderSelectSheet.svelte";

  let open = $state(true);
</script>

<!-- Picking a provider, over the screen it opens from. -->
<div class="host">
  <ConnectionsScreen />
  <ProviderSelectSheet bind:open />
</div>

<style>
  /* The sheet layer anchors to its nearest positioned ancestor, so the phone
     frame confines it rather than the page. */
  .host {
    position: relative;
    height: 100%;
  }
</style>
