<script lang="ts">
  import { ContentGroup, Icon, Notice, Row, SearchField, Sheet, Tag } from "@lib";
  import type { IconName } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  let query = $state("");

  /* One catalogue, whatever is behind each entry. Which of these is built in
     and which is a server someone runs is a fact on its own screen, so it is
     not a way of sorting this list. These are what we would suggest first,
     rather than what happens to be popular. */
  const recommended: {
    name: string;
    description: string;
    icon?: IconName;
    letter?: string;
  }[] = [
    { name: "Google", description: "Gmail, Calendar and Contacts", icon: "service/google" },
    { name: "Microsoft", description: "Outlook mail and calendar", icon: "service/microsoft" },
    { name: "iCloud", description: "Mail, calendar and contacts", icon: "service/icloud" },
    {
      name: "Apple Health",
      description: "Activity, sleep and nutrition",
      icon: "functional/heart",
    },
    { name: "Notion", description: "Notes and databases", letter: "N" },
    { name: "Other email", description: "Any account with IMAP", icon: "functional/mail" },
  ];

  const categories: {
    name: string;
    icon: IconName;
    services: { name: string; description: string; icon?: IconName; letter?: string }[];
  }[] = [
    {
      name: "Mail and calendar",
      icon: "functional/mail",
      services: [
        { name: "Google", description: "Gmail, Calendar and Contacts", icon: "service/google" },
        { name: "Microsoft", description: "Outlook mail and calendar", icon: "service/microsoft" },
        { name: "iCloud", description: "Mail, calendar and contacts", icon: "service/icloud" },
        { name: "Proton", description: "Mail and calendar", icon: "service/proton" },
        { name: "Fastmail", description: "Mail and calendar", letter: "F" },
        { name: "Other email", description: "Any account with IMAP", icon: "functional/mail" },
      ],
    },
    {
      /* Things iOS keeps behind a permission. They connect with a disclosure
         and a system prompt rather than a sign-in, and say so on the way. */
      name: "On this phone",
      icon: "functional/lock",
      services: [
        {
          name: "Apple Health",
          description: "Activity, sleep and nutrition",
          icon: "functional/heart",
        },
        { name: "Apple Calendar", description: "Events on this phone", icon: "brand/calendar" },
        {
          name: "Apple Reminders",
          description: "Lists on this phone",
          icon: "functional/check_circle",
        },
        {
          name: "Location",
          description: "Where you are, while you use Eigin",
          icon: "functional/location",
        },
      ],
    },
    {
      name: "Notes and documents",
      icon: "functional/note",
      services: [
        { name: "Notion", description: "Notes and databases", letter: "N" },
        { name: "Linear", description: "Issues and projects", icon: "service/linear" },
      ],
    },
    {
      name: "Home and devices",
      icon: "functional/sound",
      services: [
        {
          name: "Home Assistant",
          description: "Lights, heating and sensors",
          icon: "service/homeassistant",
        },
        { name: "Spotify", description: "Music and playlists", icon: "service/spotify" },
      ],
    },
    {
      name: "Travel",
      icon: "functional/location",
      services: [],
    },
  ];

  /* Browsing narrows the same sheet rather than opening another: the chip says
     where you are and clears back to the top. */
  let category = $state("none");
  const chosen = $derived(categories.find((entry) => entry.name === category));

  useStageControls(() => browse);

  const matches = (text: string) => text.toLowerCase().includes(query.trim().toLowerCase());
  const listed = $derived(chosen ? chosen.services : recommended);
  const shownServices = $derived(listed.filter((entry) => matches(entry.name)));
  const shownCategories = $derived(query || chosen ? [] : categories);
  const nothingFound = $derived(shownServices.length === 0);
</script>

<!-- Browsing is a tap in the app; here it is also driven by hand. -->
{#snippet browse()}
  <OptionSelector
    options={["none", ...categories.map((entry) => entry.name)]}
    bind:value={category}
  />
{/snippet}

<!--
  Adding anything Eigin can reach: a built-in account or a server someone
  runs, in one list.

  People arrive knowing what they want it to do, not which protocol it speaks,
  so the catalogue is sorted by that and the mechanism never appears here.
  Connect by address is always last, so the way in for anything we have never
  heard of never moves — and it promises only a try, since what answers there
  decides what we can do with it.
-->
<Sheet
  bind:open
  title="Add an integration"
  description="Use your existing accounts and tools in Eigin."
>
  {#snippet primary()}
    <div class="add">
      <SearchField bind:value={query} placeholder="Search integrations" />

      {#if chosen}
        <div class="chip">
          <Tag label={chosen.name} onclick={() => (category = "none")}>
            {#snippet trailing()}<Icon name="functional/x" size={16} />{/snippet}
          </Tag>
        </div>
      {/if}

      {#if nothingFound}
        <Notice
          tone="info"
          title={chosen ? "Nothing here yet" : "We don't know that one"}
          body={chosen
            ? "We have not added anything to this category yet. You can still connect a service by address."
            : "Eigin has a curated list of integrations, but you can try connecting any service by address."}
        />
      {/if}

      {#if shownServices.length > 0}
        <ContentGroup label={chosen ? undefined : query ? "Matches" : "Recommended"}>
          {#each shownServices as entry (entry.name)}
            <Row
              title={entry.name}
              description={entry.description}
              icon={entry.icon}
              letter={entry.letter}
              onclick={() => {}}
            />
          {/each}
        </ContentGroup>
      {/if}

      {#if shownCategories.length > 0}
        <ContentGroup label="Browse">
          {#each shownCategories as entry (entry.name)}
            <Row title={entry.name} icon={entry.icon} onclick={() => (category = entry.name)} />
          {/each}
        </ContentGroup>
      {/if}

      <ContentGroup footnote="Give Eigin an address and it will work out what is there.">
        <Row title="Connect by address" icon="functional/globe" onclick={() => {}} />
      </ContentGroup>
    </div>
  {/snippet}
</Sheet>

<style>
  .add {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: 0 var(--spacing-n16);
  }

  /* Sits with the list it filters, at the gap a group's label would take:
     the chip names the list, so the list drops its own label. */
  .chip {
    display: flex;
    margin-bottom: calc(
      var(--spacing-n8) - var(--sizing-pageLayout-gap) +
        var(--sizing-pageLayout-contentGrouping-gap)
    );
  }
</style>
