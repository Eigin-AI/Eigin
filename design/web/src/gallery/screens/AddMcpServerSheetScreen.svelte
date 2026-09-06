<script lang="ts">
  import { Sheet } from "@lib";
  import AddMcpServerScreen from "@gallery/screens/AddMcpServerScreen.svelte";
  import ConnectionsScreen from "@gallery/screens/ConnectionsScreen.svelte";

  let open = $state(true);
</script>

<!-- The add form, presented as a modal page over Connections. -->
<div class="host">
  <ConnectionsScreen />
  <Sheet bind:open title="Add MCP Server" chrome={false} fills>
    {#snippet primary()}
      <AddMcpServerScreen />
    {/snippet}
  </Sheet>
</div>

<style>
  /* The sheet layer anchors to its nearest positioned ancestor, so the phone
     frame confines it rather than the page. */
  .host {
    position: relative;
    height: 100%;
  }
</style>
