<script lang="ts">
  import { tick } from "svelte";
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
  import type { IconName, OptionChoice, ToolCall } from "@lib";
  import { lines, splitLine, splitOption, type Turn } from "@gallery/showcase/conversation";

  let { turns, pinToLatest = true }: { turns: Turn[]; pinToLatest?: boolean } = $props();

  /* Untagged option cards take the illustrations in turn, the way the app varies them. */
  const symbols: IconName[] = [
    "illustration/mountain",
    "illustration/wave",
    "illustration/moon",
    "illustration/tree",
    "illustration/flower",
  ];

  const tools = (text: string): ToolCall[] =>
    lines(text).map((line, index) => {
      const { name, detail } = splitLine(line);
      return { id: `${index}`, name, status: "completed", result: detail || undefined };
    });

  const options = (text: string): OptionChoice[] =>
    lines(text).map((line, index) => {
      const { label, description, symbol } = splitOption(line);
      return { label, description, symbol: symbol ?? symbols[index % symbols.length] };
    });

  /* The composer overlays the feed, so the feed reserves its height below. */
  let composerHeight = $state(0);
  let scroll = $state<HTMLDivElement>();

  /* Like the app, the feed rests on its latest turn, unless the shot has
     been scrolled somewhere on purpose. */
  $effect(() => {
    void JSON.stringify(turns);
    if (pinToLatest) tick().then(() => scroll?.scrollTo(0, scroll.scrollHeight));
  });
</script>

<!-- A conversation written in the chat builder, in the chat screen's chrome. -->
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

  <div
    class="scroll"
    bind:this={scroll}
    style:padding-bottom="calc({composerHeight}px + var(--spacing-n16))"
  >
    <ChatFeed>
      {#each turns as turn, index (index)}
        {#if turn.kind === "user"}
          <ChatUserMessage text={turn.text} />
        {:else if turn.kind === "agent"}
          <ChatBrandMessage>
            <Markdown text={turn.text} />
          </ChatBrandMessage>
        {:else if turn.kind === "tools"}
          <ToolGroup tools={tools(turn.text)} />
        {:else}
          <OptionsGroup options={options(turn.text)} />
        {/if}
      {/each}
    </ChatFeed>
  </div>

  <div class="composer" bind:clientHeight={composerHeight}>
    <ChatInput value="" isSendEnabled={false} onActionTap={() => {}} />
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
