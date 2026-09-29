<script lang="ts">
  import {
    ActionButton,
    BrandAvatar,
    Icon,
    NavigationBar,
    NavigationHeader,
    NavigationTab,
  } from "@lib";
  import ChatListRow from "@gallery/screens/ChatListRow.svelte";

  let tab = $state("chats");

  const sections = [
    {
      title: "Today",
      chats: [
        {
          title: "Friday mornings",
          preview: "Done. Every other Friday morning held, the first of each month untouched.",
          emoji: "🌿",
        },
        {
          title: "Lisbon in May",
          preview: "Fares drop after the 12th — want me to watch them for a week?",
          emoji: "✈️",
        },
      ],
    },
    {
      title: "Yesterday",
      chats: [
        {
          title: "Reading list",
          preview: "Three of the six are on your shelf already. I marked the other three.",
        },
      ],
    },
    {
      title: "This week",
      chats: [
        {
          title: "Kitchen rebuild",
          preview: "The joiner can start the week of the 9th if the tiles arrive first.",
          emoji: "🔨",
        },
        {
          title: "New Chat",
          preview: "No messages yet",
        },
      ],
    },
  ];
</script>

<!-- The chat list: flat rows grouped by when they were last touched. -->
<div class="chat-list">
  <NavigationHeader>
    {#snippet leading()}
      <ActionButton icon="brand/security" variant="open" size="medium" label="Filter by space" />
    {/snippet}
    {#snippet center()}
      <BrandAvatar emoji="🪶" label="Agent">
        <Icon name="brand/avatar" size="fill" />
      </BrandAvatar>
    {/snippet}
    {#snippet trailing()}
      <ActionButton icon="functional/plus" variant="open" size="medium" label="New chat" />
    {/snippet}
  </NavigationHeader>

  <div class="scroll">
    {#each sections as section (section.title)}
      <section class="section">
        <h2 class="t-miniLabel section-title">{section.title}</h2>
        <div class="rows">
          {#each section.chats as chat (chat.title)}
            <ChatListRow title={chat.title} preview={chat.preview} emoji={chat.emoji} />
          {/each}
        </div>
      </section>
    {/each}
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
  .chat-list {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    /* Grouped lists inset rows by 16 on both edges. */
    padding: 0 var(--spacing-n16) var(--spacing-n32);
  }

  .section + .section {
    margin-top: var(--spacing-n24);
  }

  .section-title {
    margin: 0 0 var(--spacing-n8);
    color: var(--color-text-standard-muted);
  }

  .rows {
    display: flex;
    flex-direction: column;
  }

  /* Hairline past the avatar, so the run reads as one column of text. */
  .rows > :global(.chat-row + .chat-row) {
    position: relative;
  }

  .rows > :global(.chat-row + .chat-row)::before {
    content: "";
    position: absolute;
    top: 0;
    left: calc(36px + var(--spacing-n16));
    right: 0;
    height: 1px;
    background: var(--color-input-standard-inactive);
  }
</style>
