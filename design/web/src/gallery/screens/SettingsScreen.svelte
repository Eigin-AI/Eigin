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

  const languages = [
    { value: "en", label: "English" },
    { value: "da", label: "Dansk" },
    { value: "de", label: "Deutsch" },
  ];

  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";

  let language = $state("en");
  let tab = $state("settings");

  /* `#/screens/settings?long` repeats the groups so the page overflows. */
  let longPage = $derived(window.location.hash.includes("long"));
</script>

<!-- Settings as iOS composes it: a header, groups of rows, and the tab bar. -->
<div class="settings">
  <ScreenScroll>
    {#snippet header()}
      <NavigationHeader title="Settings" />
    {/snippet}

    {#each Array.from({ length: longPage ? 4 : 1 }, (_, i) => i) as i (i)}
      <ContentGroup label="General">
        <OptionPicker
          title="Language"
          options={languages}
          selection={language}
          onSelect={(next) => (language = next)}
        />
        <Row title="Send feedback" accessory="none" onclick={() => {}} />
      </ContentGroup>

      <ContentGroup label="Agent">
        <Row title="Permissions" onclick={() => {}} />
        <Row title="Connections" onclick={() => {}} />
      </ContentGroup>

      <ContentGroup label="System">
        <Row title="Advanced" onclick={() => {}} />
        <Row title="About" onclick={() => {}} />
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
  .settings {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }
</style>
