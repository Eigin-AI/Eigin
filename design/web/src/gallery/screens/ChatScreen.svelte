<script lang="ts">
  import {
    ActionButton,
    BrandAvatar,
    ChatBrandMessage,
    ChatFeed,
    ChatInput,
    ChatUserMessage,
    Icon,
    Markdown,
    NavigationHeader,
    OptionsGroup,
    ToolGroup,
  } from "@lib";
  import type { OptionChoice, ToolCall } from "@lib";

  let draft = $state("");
  /* Choosing resolves the question, the way the feed replaces the item. */
  let optionsAnswered = $state(false);

  const lookups: ToolCall[] = [
    { id: "1", name: "Search notes", status: "completed", result: "3 matches" },
    { id: "2", name: "Read file", status: "completed", result: "notes/rituals.md" },
  ];

  const fridayOptions: OptionChoice[] = [
    {
      label: "Hold them all",
      description: "Every Friday morning stays clear until noon",
      symbol: "illustration/mountain",
    },
    {
      label: "Alternate weeks",
      description: "Keep one Friday in two, so the month still breathes",
      symbol: "illustration/wave",
    },
    {
      label: "Just this month",
      description: "Try it for four weeks and see how it lands",
      symbol: "illustration/moon",
    },
  ];

  const reply = `Three of your notes mention it, and they agree on the shape:

- **Mornings are yours.** Nothing lands before ten.
- **Thursdays run long**, so Friday starts slow on purpose.
- Travel weeks drop the evening block entirely.

Want me to hold Friday mornings open for the next month?`;

  /* The composer overlays the feed, so the feed reserves its height below. */
  let composerHeight = $state(0);
</script>

<!--
  A conversation mid-flow: a question, tools used to answer it, and a reply.
  The tab bar is deliberately absent — iOS hides it on this screen.
-->
<div class="chat">
  <NavigationHeader>
    {#snippet leading()}
      <ActionButton icon="functional/note" variant="open" size="medium" label="Conversations" />
    {/snippet}
    {#snippet center()}
      <BrandAvatar emoji="🪶" label="Agent">
        <Icon name="brand/avatar" size="fill" />
      </BrandAvatar>
    {/snippet}
    {#snippet trailing()}
      <ActionButton icon="functional/phone" variant="open" size="medium" label="Call" />
    {/snippet}
  </NavigationHeader>

  <div class="scroll" style:padding-bottom="calc({composerHeight}px + var(--spacing-n16))">
    <ChatFeed>
      <ChatUserMessage text="What do my notes say about how I like to work in the mornings?" />

      <ToolGroup tools={lookups} />

      <ChatBrandMessage>
        <Markdown text={reply} />
      </ChatBrandMessage>

      {#if !optionsAnswered}
        <OptionsGroup options={fridayOptions} onSelect={() => (optionsAnswered = true)} />
      {/if}

      <ChatUserMessage text="Alternate weeks, but leave the first Friday alone." />

      <ChatBrandMessage>
        <Markdown
          text="Done. Every other Friday morning held, the first of each month untouched."
        />
      </ChatBrandMessage>
    </ChatFeed>
  </div>

  <!--
    The composer anchors in a bottom safe-area inset, n16 above. That
    inset reserves room in the scroll while content still scrolls underneath,
    so the bar overlays the feed rather than cutting it off.
  -->
  <div class="composer" bind:clientHeight={composerHeight}>
    <ChatInput bind:value={draft} isSendEnabled={draft.trim().length > 0} onActionTap={() => {}} />
  </div>
</div>

<style>
  .chat {
    position: relative;
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

  /* No backdrop: the bar is the capsule, and the feed shows around it, the
     way it does on iOS. */
  .composer {
    position: absolute;
    right: 0;
    bottom: 0;
    left: 0;
    padding-bottom: max(
      var(--spacing-n8),
      var(--eigin-safe-area-bottom, env(safe-area-inset-bottom))
    );
  }
</style>
