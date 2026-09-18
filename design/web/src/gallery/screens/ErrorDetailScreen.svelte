<script lang="ts">
  import ChatScreen from "@gallery/screens/ChatScreen.svelte";
  import ErrorDetailSheet from "@gallery/screens/ErrorDetailSheet.svelte";

  let open = $state(true);
</script>

<!-- A failed turn, opened from the feed it broke. -->
<div class="host">
  <ChatScreen />
  <ErrorDetailSheet bind:open />
</div>

<style>
  /* The sheet layer anchors to its nearest positioned ancestor, so the phone
     frame confines it rather than the page. */
  .host {
    position: relative;
    height: 100%;
  }
</style>
