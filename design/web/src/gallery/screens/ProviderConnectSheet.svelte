<script lang="ts">
  import { Button, Icon, Sheet, SubtleActionButton, TextInput } from "@lib";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* The three flows the sheet can be in, driven by the preset's auth method. */
  const flows = ["oauth done", "api key", "custom", "error"] as const;
  let flow = $state<(typeof flows)[number]>("api key");

  useStageControls(() => flowControl);

  let apiKey = $state("");
  let name = $state("");
  let baseURL = $state("");
</script>

<!-- The app picks the flow from the preset; here it is driven by hand. -->
{#snippet flowControl()}
  <OptionSelector options={flows} bind:value={flow} />
{/snippet}

<!--
  The second step of adding a provider: whichever connection the chosen preset
  needs. OAuth signs in and lands on a confirmation; an API-key preset asks for
  the key; custom asks for a name and base URL too. Every path keeps a way back
  to the picker.
-->
<Sheet
  bind:open
  title={flow === "custom" ? "Custom Provider" : "Anthropic"}
  description={flow === "custom"
    ? "Requires an OpenAI-compatible API. Check with your provider for the base URL and API key."
    : "Generate an API key in the Anthropic Console under Settings."}
>
  {#snippet primary()}
    <div class="flow">
      {#if flow === "oauth done"}
        <div class="centered">
          <span class="tick"><Icon name="functional/check_circle" size={48} /></span>
          <div class="lines">
            <span class="t-titleXS">Connected to Anthropic</span>
            <span class="t-note muted"
              >Make sure you have credits on your account before continuing.</span
            >
          </div>
          <Button
            label="Add Credits on Anthropic"
            variant="secondary"
            size="medium"
            onclick={() => {}}
          >
            {#snippet trailing()}<Icon name="functional/arrow/up_right" size={16} />{/snippet}
          </Button>
        </div>

        <div class="actions">
          <Button label="Continue" onclick={() => {}} />
          <Button label="Change Provider" variant="secondary" onclick={() => {}} />
        </div>
      {:else if flow === "error"}
        <div class="centered">
          <span class="t-titleXS">Connection failed</span>
          <span class="t-note muted">You can try again or add an API key manually.</span>
        </div>
        <div class="actions">
          <Button label="Try Again" onclick={() => {}} />
          <Button label="Change Provider" variant="secondary" onclick={() => {}} />
        </div>
      {:else if flow === "custom"}
        <div class="actions">
          <TextInput label="Name" bind:value={name} />
          <TextInput label="Base URL" bind:value={baseURL} />
          <TextInput label="API Key" bind:value={apiKey} isSecure />
          <Button label="Connect" onclick={() => {}} disabled={!name || !baseURL || !apiKey} />
        </div>
      {:else}
        <div class="actions">
          <TextInput label="API Key" bind:value={apiKey} isSecure />
          <Button label="Connect" onclick={() => {}} disabled={!apiKey} />
          <SubtleActionButton label="Get API Key" size="medium" onclick={() => {}}>
            {#snippet icon()}<Icon name="functional/arrow/up_right" size={24} />{/snippet}
          </SubtleActionButton>
        </div>
      {/if}
    </div>
  {/snippet}
</Sheet>

<style>
  .flow {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: 0 var(--spacing-n24);
  }

  .centered {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n16);
    text-align: center;
  }

  .tick {
    display: inline-flex;
    color: var(--color-accent);
  }

  .lines {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n8);
  }

  .muted {
    color: var(--color-text-standard-muted);
  }

  .actions {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }
</style>
