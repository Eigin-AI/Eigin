<script lang="ts">
  import SoftEdgeScroll from "@lib/internal/SoftEdgeScroll.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "./stageControls.svelte";
  let attributionState = $state("loaded");
  useStageControls(() => (weatherConversation ? attributionControls : undefined));
  import WeatherAttribution from "./WeatherAttribution.svelte";
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

  const weatherReply =
    "I'd go tomorrow. This afternoon is around **12°C**, with rain likely and a brisk wind along the water.\n\nTomorrow looks drier, with lighter winds. Late morning would be a good time for a walk.";

  const reply = `Three of your notes mention it, and they agree on the shape:

- **Mornings are yours.** Nothing lands before ten.
- **Thursdays run long**, so Friday starts slow on purpose.
- Travel weeks drop the evening block entirely.

Want me to hold Friday mornings open for the next month?`;

  /* `#/screens/chat?long` repeats the conversation so the feed overflows. */
  let longConversation = $derived(window.location.hash.includes("long"));
  let weatherConversation = $derived(window.location.hash.includes("weather"));
</script>

{#snippet attributionControls()}
  <OptionSelector options={["loaded", "loading", "unavailable"]} bind:value={attributionState} />
{/snippet}

<!--
  A conversation mid-flow: a question, tools used to answer it, and a reply.
  The tab bar is deliberately absent — iOS hides it on this screen.
-->
<div class="chat">
  <SoftEdgeScroll>
    {#snippet header()}
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
    {/snippet}
    {#snippet footer()}
      <ChatInput
        bind:value={draft}
        isSendEnabled={draft.trim().length > 0}
        onActionTap={() => {}}
      />
    {/snippet}
    <ChatFeed>
      {#if weatherConversation}
        <ChatUserMessage
          text="Can I walk along the harbour this afternoon, or should I wait until tomorrow?"
        />
        <ToolGroup
          tools={[
            {
              id: "weather",
              name: "Get weather",
              status: "completed",
              result: "Copenhagen · Current conditions and forecast",
            },
          ]}
        />
        <ChatBrandMessage>
          <Markdown text={weatherReply} />
          <WeatherAttribution
            state={attributionState}
            onRetry={() => (attributionState = "loaded")}
          />
        </ChatBrandMessage>
      {:else}
        {#each Array.from({ length: longConversation ? 4 : 1 }, (_, i) => i) as i (i)}
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
        {/each}
      {/if}
    </ChatFeed>
  </SoftEdgeScroll>
</div>

<style>
  .chat {
    position: relative;
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }
</style>
