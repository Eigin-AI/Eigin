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

  let language = $state("en");
  let tab = $state("settings");
</script>

<!-- Settings as iOS composes it: a header, groups of rows, and the tab bar. -->
<div class="settings">
  <NavigationHeader title="Settings" />

  <div class="scroll">
    <div class="groups">
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
    </div>
  </div>

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
</div>

<style>
  .settings {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
  }

  /* PageLayout.gap between groups, n16 horizontal, n8 top, n32 bottom. */
  .groups {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: var(--spacing-n8) var(--spacing-n16) var(--spacing-n32);
  }
</style>
