<script lang="ts">
  import { ContentGroup, Notice, Row, SearchField, Sheet } from "@lib";
  import type { IconName } from "@lib";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  let query = $state("");

  /* Providers you have already connected are left out entirely: you reached
     this sheet from the list they are on, so offering them again would be
     offering a thing you cannot do. */
  const connected = ["Anthropic"];

  /* Sign-in first: nothing to paste, nothing to lose. OpenAI appears in both
     groups because it genuinely offers both, and the group you pick from is
     the way you want to connect. */
  const signIn: { name: string; icon: IconName }[] = [
    { name: "EUrouter", icon: "provider/eurouter" },
    { name: "OpenRouter", icon: "provider/openrouter" },
    { name: "OpenAI", icon: "provider/openai" },
  ];

  const apiKey: { name: string; icon: IconName }[] = [
    { name: "OpenAI", icon: "provider/openai" },
    { name: "Anthropic", icon: "provider/anthropic" },
    { name: "Google", icon: "provider/google" },
    { name: "Mistral", icon: "provider/mistral" },
    { name: "Groq", icon: "provider/groq" },
    { name: "Berget AI", icon: "provider/berget" },
    { name: "Infercom", icon: "provider/infercom" },
  ];

  const available = (list: { name: string; icon: IconName }[]) =>
    list.filter(
      (preset) =>
        !connected.includes(preset.name) &&
        preset.name.toLowerCase().includes(query.trim().toLowerCase()),
    );

  const shownSignIn = $derived(available(signIn));
  const shownApiKey = $derived(available(apiKey));
  const nothingFound = $derived(shownSignIn.length + shownApiKey.length === 0);
</script>

<!--
  Picking a provider to add.

  Two groups, named for what you will be asked to do rather than for the
  protocol behind it, and sign-in first because it asks least of you. Connect
  by address is always the last thing in the sheet, so the way in for anything
  we have never heard of never moves.
-->
<Sheet
  bind:open
  title="Add a provider"
  description="Eigin uses cloud AI to think. You can connect more than one, and switch anytime."
>
  {#snippet primary()}
    <div class="select">
      <SearchField bind:value={query} placeholder="Search providers" />

      <!-- A search that finds nothing is not a dead end here: the last group
           in the sheet takes anything, so the notice hands straight to it. -->
      {#if nothingFound}
        <Notice
          tone="info"
          title="We don't know that one"
          body="Eigin has a curated list of provider presets, but you can connect any AI provider with an OpenAI-compatible API by address."
        />
      {/if}

      {#if shownSignIn.length > 0}
        <ContentGroup label="Sign in">
          {#each shownSignIn as preset (preset.name)}
            <Row title={preset.name} icon={preset.icon} onclick={() => {}} />
          {/each}
        </ContentGroup>
      {/if}

      {#if shownApiKey.length > 0}
        <ContentGroup label="Paste an API key">
          {#each shownApiKey as preset (preset.name)}
            <Row title={preset.name} icon={preset.icon} onclick={() => {}} />
          {/each}
        </ContentGroup>
      {/if}

      <ContentGroup footnote="Anything with an OpenAI-compatible API.">
        <Row title="Connect by address" icon="functional/globe" onclick={() => {}} />
      </ContentGroup>
    </div>
  {/snippet}
</Sheet>

<style>
  .select {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: 0 var(--spacing-n16);
  }
</style>
