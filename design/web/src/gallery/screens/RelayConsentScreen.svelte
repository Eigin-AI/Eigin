<script lang="ts">
  import EiginProviderScreen from "@gallery/screens/EiginProviderScreen.svelte";
  import RelayConsentSheet from "@gallery/screens/RelayConsentSheet.svelte";

  let open = $state(true);
</script>

<!-- Asking before the relay, over the screen it opens from. -->
<div class="host">
  <EiginProviderScreen />
  <RelayConsentSheet bind:open />
</div>

<style>
  /* The sheet layer anchors to its nearest positioned ancestor, so the phone
     frame confines it rather than the page. */
  .host {
    position: relative;
    height: 100%;
  }
</style>
