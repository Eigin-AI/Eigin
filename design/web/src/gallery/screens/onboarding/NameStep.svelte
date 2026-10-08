<script lang="ts">
  import { Button, Sheet, TextInput } from "@lib";

  let { name = $bindable(""), onContinue }: { name?: string; onContinue: () => void } = $props();

  let showPrivacy = $state(false);
</script>

<!--
  Asks the user's name: a quiet link answering why a private app asks, the
  field, and the button. Same three rows as the inference step.
-->
<div class="actions">
  <button class="link t-navTab" type="button" onclick={() => (showPrivacy = true)}>
    Why do you need my name?
  </button>

  <div class="group">
    <TextInput label="Your name" bind:value={name} />
    <Button label="Continue" disabled={name.trim().length === 0} onclick={onContinue} />
  </div>
</div>

<Sheet bind:open={showPrivacy} title="This is your space">
  {#snippet primary()}
    <p class="t-body privacy">
      Everything you tell me is stored on your device, and nowhere else.<br /><br />If you’d rather
      not share your real name, that’s also okay. Use a nickname, an initial, or just write
      “Anonymous”. It’s up to you.
    </p>
  {/snippet}
</Sheet>

<style>
  .actions {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n16);
    margin-top: auto;
  }

  .group {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
    align-self: stretch;
  }

  .link {
    padding: 0;
    border: none;
    background: none;
    color: var(--color-text-standard-link);
    cursor: pointer;
  }

  .privacy {
    margin: 0;
    padding: 0 var(--spacing-n24);
    color: var(--color-text-standard-muted);
  }
</style>
