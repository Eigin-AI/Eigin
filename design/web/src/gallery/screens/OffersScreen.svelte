<script lang="ts">
  import { ActionButton, ContentGroup, NavigationHeader, Row, SearchField } from "@lib";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";

  const defaults = [
    "Create issue",
    "Update issue",
    "Search issues",
    "List projects",
    "Create project",
    "Add comment",
    "List comments",
    "Assign issue",
    "Set issue status",
    "List teams",
    "List labels",
    "Create label",
    "Search documents",
    "Create document",
    "List cycles",
    "Move issue to cycle",
    "List users",
    "Archive issue",
    "Link issues",
    "List workflows",
  ];

  /* Tools, skills, capabilities: whatever this connection offered, in the
     order it offered them. */
  const {
    title = "Tools",
    noun = "tools",
    footnote = "Eigin picks the ones a chat needs.",
    items = defaults,
  }: { title?: string; noun?: string; footnote?: string; items?: string[] } = $props();

  let query = $state("");

  const shown = $derived(
    items.filter((item) => item.toLowerCase().includes(query.trim().toLowerCase())),
  );
</script>

<!--
  Everything one connection offers, read-only: a server's tools, an agent's
  skills, an account's capabilities.

  Unlike a provider's models there is no choice to make — Eigin picks what a
  chat needs, and setting that by hand would be a setting nobody has the
  information to set. So this is a list to check rather than to change, which
  is why it needs no groups and no controls: the only interaction is finding
  something in it.
-->
<div class="list">
  <ScreenScroll>
    {#snippet header()}
      <NavigationHeader {title}>
        {#snippet leading()}
          <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
        {/snippet}
      </NavigationHeader>
    {/snippet}

    <SearchField bind:value={query} placeholder="Search {items.length} {noun}" />

    {#if shown.length === 0}
      <p class="t-note empty">Nothing matches “{query}”.</p>
    {:else}
      <ContentGroup {footnote}>
        {#each shown as item (item)}
          <Row title={item} accessory="none" />
        {/each}
      </ContentGroup>
    {/if}
  </ScreenScroll>
</div>

<style>
  .list {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  .empty {
    margin: 0;
    padding: 0 var(--spacing-n24);
    color: var(--color-text-standard-muted);
  }
</style>
