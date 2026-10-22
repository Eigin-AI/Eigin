<script lang="ts">
  import { Sheet } from "@lib";
  import AiConsent from "@gallery/screens/AiConsent.svelte";

  let { open = $bindable(false) }: { open?: boolean } = $props();
</script>

<!--
  Asking before the first conversation goes through the relay. Your own
  providers ask as the last step of connecting; the relay is always there, so
  it asks in a sheet of its own.
-->
<Sheet
  bind:open
  title="Share with Eigin?"
  description="To reply, Eigin sends your conversation to a private cloud AI."
>
  {#snippet primary()}
    <div class="body">
      <AiConsent
        recipient="relay"
        onAllow={() => (open = false)}
        onDecline={() => (open = false)}
      />
    </div>
  {/snippet}
</Sheet>

<style>
  .body {
    padding: 0 var(--spacing-n16);
  }
</style>
