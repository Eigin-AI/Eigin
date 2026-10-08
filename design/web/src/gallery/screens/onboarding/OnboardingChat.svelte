<script lang="ts">
  import {
    ActionButton,
    ChatBrandMessage,
    ChatFeed,
    ChatInput,
    ChatUserMessage,
    Markdown,
    NavigationHeader,
    ThinkingIndicator,
    ToolGroup,
  } from "@lib";
  import type { ToolCall } from "@lib";
  import { untrack } from "svelte";
  import OnboardingAvatar from "@gallery/screens/onboarding/OnboardingAvatar.svelte";
  import OnboardingReveal from "@gallery/screens/onboarding/OnboardingReveal.svelte";
  import { pause, speak } from "@gallery/screens/onboarding/speak";
  import { script } from "@gallery/screens/onboarding/conversation";
  import { avatarProgress } from "@gallery/screens/onboarding/steps";

  let {
    name,
    priority,
    revealing,
    speed = 1,
    onFinish,
    onBack,
  }: {
    name: string;
    priority: string;
    /** The agent has sealed itself and is introducing itself. */
    revealing: boolean;
    /** Plays the reveal slower, for inspecting it. */
    speed?: number;
    onFinish: () => void;
    onBack: () => void;
  } = $props();

  type Item =
    | { kind: "agent"; text: string }
    | { kind: "user"; text: string }
    | { kind: "tools"; tools: ToolCall[] };

  // svelte-ignore state_referenced_locally
  const turns = script(name || "there", priority);

  let items = $state<Item[]>([]);
  let streaming = $state<string | undefined>();
  let thinking = $state(false);
  let turn = $state(0);
  let fill = $state(avatarProgress.conversation);
  let draft = $state(turns[0].suggestion ?? "");
  let composerHeight = $state(0);
  let feed = $state<HTMLDivElement>();

  const busy = $derived(thinking || streaming !== undefined || revealing);

  /* Jumping straight to the reveal shows the conversation it ends. */
  // svelte-ignore state_referenced_locally
  if (revealing) {
    items = turns.flatMap((each): Item[] => [
      ...(each.tools ? [{ kind: "tools" as const, tools: each.tools }] : []),
      { kind: "agent", text: each.reply },
      ...(each.suggestion ? [{ kind: "user" as const, text: each.suggestion }] : []),
    ]);
    fill = 1;
  }

  const controller = new AbortController();
  $effect(() => () => controller.abort());

  /** Plays the agent's next turn: a think, its tools, then the streamed reply. */
  async function respond() {
    const { signal } = controller;
    const next = turns[turn];
    thinking = true;
    await pause(900, signal);
    thinking = false;
    if (next.tools) items.push({ kind: "tools", tools: next.tools });
    streaming = "";
    await speak(next.reply, (shown) => (streaming = shown), signal);
    if (signal.aborted) return;
    items.push({ kind: "agent", text: next.reply });
    streaming = undefined;
    fill = next.fill;
    draft = next.suggestion ?? "";

    if (next.done) {
      await pause(1200, signal);
      if (!signal.aborted) onFinish();
    }
    turn += 1;
  }

  function send() {
    const text = draft.trim();
    if (!text || busy) return;
    items.push({ kind: "user", text });
    draft = "";
    respond();
  }

  /* The agent speaks first. */
  // svelte-ignore state_referenced_locally
  if (!revealing) untrack(respond);

  /* Follow the conversation down as it grows. */
  $effect(() => {
    void items.length;
    void streaming;
    feed?.scrollTo({ top: feed.scrollHeight });
  });
</script>

<!--
  The onboarding conversation: a real, restricted agent chat. The agent opens
  knowing the name and priority, gets to know you, and writes what it learns
  into its core. The avatar in the header fills as it does. Here the agent's
  side is scripted, and your next reply waits in the composer.
-->
<div class="chat">
  <NavigationHeader>
    {#snippet leading()}
      <ActionButton
        icon="functional/arrow/left"
        variant="open"
        size="medium"
        label="Back"
        onclick={onBack}
      />
    {/snippet}
    {#snippet center()}
      <OnboardingAvatar progress={fill} size={56} />
    {/snippet}
  </NavigationHeader>

  <div
    class="scroll"
    bind:this={feed}
    style:padding-bottom="calc({composerHeight}px + var(--spacing-n16))"
  >
    <ChatFeed>
      {#each items as item, index (index)}
        {#if item.kind === "agent"}
          <ChatBrandMessage><Markdown text={item.text} /></ChatBrandMessage>
        {:else if item.kind === "user"}
          <ChatUserMessage text={item.text} />
        {:else}
          <ToolGroup tools={item.tools} />
        {/if}
      {/each}

      {#if thinking}
        <ChatBrandMessage><ThinkingIndicator /></ChatBrandMessage>
      {:else if streaming !== undefined}
        <ChatBrandMessage><Markdown text={streaming} /></ChatBrandMessage>
      {/if}
    </ChatFeed>
  </div>

  <div class="composer" bind:clientHeight={composerHeight}>
    <ChatInput bind:value={draft} isSendEnabled={!busy && draft.trim().length > 0} onSend={send} />
  </div>

  {#if revealing}
    <div class="reveal">
      <OnboardingReveal
        agentName="Ford"
        {speed}
        emoji="🛰️"
        digest="I’m here to keep your days in order without making a fuss about it: a short rundown each morning, and a nudge before the small things slip. Everything we do stays yours."
      />
    </div>
  {/if}
</div>

<style>
  /* Positioned, so the reveal can lay itself over the whole screen. */
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
    padding-top: var(--spacing-n16);
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

  .reveal {
    position: absolute;
    inset: 0;
    animation: fade-in var(--motion-slow) ease-out both;
  }

  @keyframes fade-in {
    from {
      opacity: 0;
    }
  }
</style>
