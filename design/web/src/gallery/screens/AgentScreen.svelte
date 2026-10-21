<script lang="ts">
  import {
    ContentGroup,
    Icon,
    NavigationBar,
    NavigationHeader,
    NavigationTab,
    OptionPicker,
    Row,
  } from "@lib";

  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";

  let tab = $state("agent");

  /* `#/screens/agent?long` repeats the groups so the page overflows. */
  let longPage = $derived(window.location.hash.includes("long"));

  let name = $state("Wren");
  let editingName = $state(false);

  let voice = $state("system");
  let initiative = $state("balanced");
  let provider = $state("eigin");

  const voices = [
    { value: "system", label: "System default" },
    { value: "samantha", label: "Samantha" },
    { value: "daniel", label: "Daniel", detail: "British" },
  ];

  const initiatives = [
    { value: "quiet", label: "Quiet", detail: "Speaks only when asked" },
    { value: "balanced", label: "Balanced", detail: "Chimes in when it matters" },
    { value: "forward", label: "Forward", detail: "Starts things on its own" },
  ];

  const providers = [
    { value: "eigin", label: "Eigin" },
    { value: "openai", label: "OpenAI" },
    { value: "local", label: "On device" },
  ];

  const initiativeSummary = $derived(
    initiatives.find((level) => level.value === initiative)?.detail,
  );
</script>

<!-- The agent tab: who the agent is, how it speaks, and what runs it. -->
<div class="agent">
  <ScreenScroll>
    {#snippet header()}
      <NavigationHeader title="Agent" />
    {/snippet}

    {#each Array.from({ length: longPage ? 4 : 1 }, (_, i) => i) as i (i)}
      <ContentGroup>
        <!-- Hero row: the name swaps for a text field in place. -->
        <div class="identity">
          <button class="emoji" type="button" aria-label="Change avatar">🪶</button>
          {#if editingName}
            <!-- svelte-ignore a11y_autofocus -->
            <input
              class="t-titleM name-field"
              bind:value={name}
              autofocus
              onblur={() => (editingName = false)}
              onkeydown={(event) => {
                if (event.key === "Enter") editingName = false;
              }}
            />
          {:else}
            <button class="t-titleM name" type="button" onclick={() => (editingName = true)}>
              {name}
            </button>
          {/if}
        </div>

        <OptionPicker
          title="Voice"
          options={voices}
          selection={voice}
          onSelect={(next) => (voice = next)}
        />

        <OptionPicker
          title="Initiative"
          description={initiativeSummary}
          options={initiatives}
          selection={initiative}
          onSelect={(next) => (initiative = next)}
        />

        <Row title="Advanced" onclick={() => {}} />
      </ContentGroup>

      <ContentGroup label="Model">
        <OptionPicker
          title="Provider"
          options={providers}
          selection={provider}
          onSelect={(next) => (provider = next)}
        />
        <Row title="Model" value="Auto" onclick={() => {}} />
      </ContentGroup>
    {/each}
    {#snippet footer()}
      <NavigationBar>
        <NavigationTab label="Chats" selected={tab === "chats"} onclick={() => (tab = "chats")}>
          {#snippet icon()}<Icon name="brand/avatar" size="fill" />{/snippet}
        </NavigationTab>
        <NavigationTab label="Agent" selected={tab === "agent"} onclick={() => (tab = "agent")}>
          {#snippet icon()}<Icon name="functional/avatar" size="fill" />{/snippet}
        </NavigationTab>
        <NavigationTab
          label="Settings"
          selected={tab === "settings"}
          onclick={() => (tab = "settings")}
        >
          {#snippet icon()}<Icon name="brand/settings" size="fill" />{/snippet}
        </NavigationTab>
      </NavigationBar>
    {/snippet}
  </ScreenScroll>
</div>

<style>
  .agent {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  .identity {
    display: flex;
    align-items: center;
    gap: var(--spacing-n12);
    padding: var(--spacing-n16) var(--spacing-n24);
  }

  .emoji {
    font-size: 40px;
    line-height: 1;
    padding: 0;
    border: none;
    background: none;
    cursor: pointer;
  }

  /* A button and an input carry the UA's own font, so the reset must not
     hand them `inherit` — that beats the typography class and drops the name
     into the serif body face. The class owns the family. */
  .name,
  .name-field {
    padding: 0;
    border: none;
    background: none;
    color: var(--color-text-standard-base);
    text-align: left;
  }

  .name {
    cursor: text;
  }

  .name-field {
    min-width: 0;
    flex: 1;
    outline: none;
  }
</style>
