<script lang="ts">
  import ChatScreen from "@gallery/screens/ChatScreen.svelte";
  import ToolDetailSheet from "@gallery/screens/ToolDetailSheet.svelte";

  let open = $state(true);
</script>

<!-- One tool call opened from the feed that ran it. -->
<div class="host">
  <ChatScreen />
  <ToolDetailSheet bind:open />
</div>

<style>
  /* The sheet layer anchors to its nearest positioned ancestor, so the phone
     frame confines it rather than the page. */
  .host {
    position: relative;
    height: 100%;
  }
</style>
