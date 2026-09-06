<script lang="ts">
  import ConnectionsScreen from "@gallery/screens/ConnectionsScreen.svelte";
  import AddIntegrationSheet from "@gallery/screens/AddIntegrationSheet.svelte";

  let open = $state(true);
</script>

<!-- Adding an integration, over the screen it opens from. -->
<div class="host">
  <ConnectionsScreen />
  <AddIntegrationSheet bind:open />
</div>

<style>
  /* The sheet layer anchors to its nearest positioned ancestor, so the phone
     frame confines it rather than the page. */
  .host {
    position: relative;
    height: 100%;
  }
</style>
