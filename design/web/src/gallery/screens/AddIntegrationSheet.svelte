<script lang="ts">
  import { ContentGroup, Icon, Row, Sheet, Tag } from "@lib";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* The grid and the search field are both filters over the bundled types.
     An active category shows as a removable chip; clearing it shows the grid. */
  const categories = [
    { name: "Email", icon: "functional/mail", available: true },
    { name: "Family & School", icon: "functional/school", available: true },
    { name: "Health", icon: "functional/heart", available: false },
    { name: "Music", icon: "functional/music", available: false },
  ] as const;

  const emailTypes = [
    { name: "Google", description: "Gmail, Calendar and Contacts", connected: true },
    { name: "Microsoft", description: "Outlook mail and calendar", connected: false },
    {
      name: "Other email (IMAP)",
      description: "Connect any email account with IMAP, such as iCloud.",
      connected: false,
    },
  ];

  let category = $state<string | undefined>(undefined);
  let search = $state("");

  const filtered = $derived(category === "Email" || search ? emailTypes : undefined);
</script>

<!--
  Connecting a new integration: pick a type, run its auth, save. The category
  grid stands in for browsing; picking one filters to a list and leaves a chip
  to clear. A type already connected is inert and ticked — one account per type.
-->
<Sheet
  bind:open
  title="Add Integration"
  description="Search for a service, or browse by what you need it to do."
>
  {#snippet primary()}
    <div class="add">
      <label class="search">
        <Icon name="functional/search" size={20} />
        <input class="t-description" placeholder="Search integrations" bind:value={search} />
      </label>

      <div class="results">
        {#if category}
          <div class="chip">
            <Tag label={category} onclick={() => (category = undefined)}>
              {#snippet trailing()}<Icon name="functional/x" size={16} />{/snippet}
            </Tag>
          </div>
        {/if}

        {#if filtered}
          <ContentGroup>
            {#each filtered as type (type.name)}
              {#if type.connected}
                <Row
                  title={type.name}
                  description={type.description}
                  accessory="none"
                  trailing={connected}
                />
              {:else}
                <Row title={type.name} description={type.description} onclick={() => {}} />
              {/if}
            {/each}
          </ContentGroup>
        {:else}
          <div class="grid">
            {#each categories as entry (entry.name)}
              <button
                class="tile"
                class:inert={!entry.available}
                type="button"
                disabled={!entry.available}
                onclick={() => (category = entry.name)}
              >
                <Icon name={entry.icon} size={28} />
                <span class="t-button">{entry.name}</span>
              </button>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  {/snippet}
</Sheet>

{#snippet connected()}
  <span class="tick"><Icon name="functional/check_circle" size={20} /></span>
{/snippet}

<style>
  .add {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: 0 var(--spacing-n16);
  }

  .search {
    display: flex;
    align-items: center;
    gap: var(--spacing-n8);
    box-sizing: border-box;
    height: var(--sizing-input-height);
    padding: 0 var(--sizing-input-px-left);
    border-radius: var(--radius-full);
    background: var(--color-input-standard-active);
    color: var(--color-text-standard-muted);
  }

  .search input {
    flex: 1;
    min-width: 0;
    border: none;
    background: transparent;
    color: var(--color-text-standard-base);
    font: inherit;
    outline: none;
  }

  /* The chip is grouped with the list it filters. */
  .results {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }

  .chip {
    display: flex;
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
    text-align: center;
    cursor: pointer;
  }

  /* A category awaiting its first provider stays visible but inert. */
  .tile.inert {
    opacity: 0.5;
    cursor: default;
  }

  .tick {
    display: inline-flex;
    color: var(--color-icon-signal-approve);
  }
</style>
