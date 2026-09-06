<script lang="ts">
  import { slide } from "svelte/transition";
  import { Icon, Sheet, SubtleActionButton } from "@lib";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* OAuth presets are featured; the rest sit behind a fold as a grid. */
  const oauth = [
    { name: "EUrouter", emoji: "🇪🇺" },
    { name: "OpenRouter", emoji: "🌐" },
  ];

  /* The set carries the provider marks already; no need for a stand-in. */
  const apiKeyPresets = [
    { name: "OpenAI", logo: "provider/openai" },
    { name: "Anthropic", logo: "provider/anthropic" },
    { name: "Google", logo: "provider/google" },
    { name: "Mistral", logo: "provider/mistral" },
    { name: "Berget AI", logo: "provider/berget" },
    { name: "Infercom", logo: "provider/infercom" },
  ] as const;

  let showKeys = $state(true);
</script>

<!--
  The first step of adding a provider. OAuth providers are offered outright;
  everything that wants an API key waits behind a fold, with the custom
  provider at the end of the grid.
-->
<Sheet
  bind:open
  title="AI Provider"
  description="Eigin uses cloud AI to think: the choice is yours. You can switch anytime."
>
  {#snippet primary()}
    <div class="select">
      <div class="featured">
        {#each oauth as preset (preset.name)}
          <div class="oauth">
            <span class="flag">{preset.emoji}</span>
            <SubtleActionButton label="Use {preset.name}" size="medium" onclick={() => {}}>
              {#snippet icon()}<Icon name="functional/arrow/right" size={24} />{/snippet}
            </SubtleActionButton>
          </div>
        {/each}
      </div>

      <div class="fold">
        <button class="fold-head" type="button" onclick={() => (showKeys = !showKeys)}>
          <span class="t-navTab">Or connect with an API key</span>
          <span class="chevron" class:open={showKeys}>
            <Icon name="functional/chevron/down" size={16} />
          </span>
        </button>

        {#if showKeys}
          <!-- The fold rolls open, and the sheet grows with it. -->
          <div class="keys" transition:slide={{ duration: 250 }}>
            <div class="grid">
              {#each apiKeyPresets as preset (preset.name)}
                <button class="tile" type="button">
                  <span class="logo"><Icon name={preset.logo} size={36} /></span>
                  <span class="t-button">{preset.name}</span>
                </button>
              {/each}
            </div>
            <SubtleActionButton label="Custom Provider" size="medium" onclick={() => {}}>
              {#snippet icon()}<Icon name="functional/plus" size={24} />{/snippet}
            </SubtleActionButton>
          </div>
        {/if}
      </div>

      <p class="t-note disclosure">
        Connecting your own provider sends your conversations to that company under their terms.
      </p>
    </div>
  {/snippet}
</Sheet>

<style>
  .select {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: 0 var(--spacing-n24);
  }

  .featured {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }

  /* A label and the thing it labels: the header grouping gap. */
  .fold {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-headerGrouping-gap);
  }

  .keys {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }

  .oauth {
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
  }

  /* The icon rides in the button's trailing slot, and the spacer in there
     pushes the button across the row beside the flag. */
  .oauth :global(.eigin-btn) {
    flex: 1;
  }

  .flag {
    font-size: 28px;
    line-height: 1;
  }

  .fold-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: 0;
    border: none;
    background: transparent;
    color: var(--color-text-standard-muted);
    font-family: inherit;
    cursor: pointer;
  }

  /* Closed points right, open points down — one glyph, turned. */
  .chevron {
    display: inline-flex;
    transform: rotate(-90deg);
    transition: transform var(--motion-normal) var(--motion-easing-smooth);
  }

  .chevron.open {
    transform: rotate(0deg);
  }

  .grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }

  .tile {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n16);
    padding: var(--spacing-n24) var(--spacing-n8);
    border: none;
    border-radius: var(--radius-card);
    background: var(--color-button-standard-secondary);
    color: var(--color-text-standard-base);
    font-family: inherit;
    cursor: pointer;
  }

  .logo {
    color: var(--color-text-standard-muted);
  }

  .disclosure {
    margin: 0;
    color: var(--color-text-standard-muted);
  }
</style>
