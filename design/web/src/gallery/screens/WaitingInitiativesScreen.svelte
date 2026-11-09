<script lang="ts">
  import {
    ActionButton,
    BrandAvatar,
    Button,
    ChatBrandMessage,
    ChatFeed,
    ChatInput,
    ChatUserMessage,
    EmptyState,
    Icon,
    Markdown,
    NavigationHeader,
    Sheet,
  } from "@lib";
  import SoftEdgeScroll from "@lib/internal/SoftEdgeScroll.svelte";
  import ChatListScreen from "./ChatListScreen.svelte";
  import { useStageControls } from "./stageControls.svelte";

  // Fixed relative times keep this gallery scenario stable across visits.
  const invitations = [
    {
      id: "appointment-follow-up",
      context: "Your appointment",
      time: "Today, 12:45",
      hoursAgo: 0.25,
      message:
        "Here’s the checklist we agreed on for your appointment: bring your notes, your medication list, and the questions you wanted to ask. Which part would you like to go over?",
      reply:
        "Here’s the checklist we agreed on for your appointment: bring your notes, your medication list, and the questions you wanted to ask. Which part would you like to go over?",
    },
    {
      id: "week",
      context: "Your weekly review",
      time: "Today, 09:00",
      hoursAgo: 4,
      message:
        "Ready for your weekly review? Let’s look back at what went well and pick a focus for next week.",
      reply: "Let’s start with this week. What felt like progress, even if it wasn’t on your list?",
    },
    {
      id: "walk",
      context: "A little time outside",
      time: "Today, 12:30",
      hoursAgo: 0.5,
      message: "Time for a little walk?",
      reply:
        "Take a little time outside. You don’t need to make it a workout. Want to choose a time to head out?",
    },
    {
      id: "read",
      context: "Your reading habit",
      time: "Yesterday, 19:00",
      hoursAgo: 18,
      message: "Find your next read?",
      reply:
        "What are you in the mood for — something to get lost in, or something that gives you a new idea?",
    },
    {
      id: "weekend",
      context: "Weekend plans",
      time: "Yesterday, 16:00",
      hoursAgo: 21,
      message: "Shall we make a little plan for the weekend?",
      reply: "What would you like to make time for this weekend?",
    },
    {
      id: "plants",
      context: "Your plants",
      time: "Monday, 10:00",
      hoursAgo: 27,
      message: "Time to check on your plants?",
      reply: "Have a look at the soil first. Which plants seem thirsty?",
    },
    {
      id: "meals",
      context: "Meal planning",
      time: "Sunday, 17:00",
      hoursAgo: 44,
      message: "Want to plan a few easy meals?",
      reply: "What do you already have in the kitchen?",
    },
    {
      id: "tomorrow",
      context: "Tomorrow’s plans",
      time: "Tomorrow, 09:00",
      hoursAgo: -20,
      message: "Ready to plan your day?",
      reply: "What’s on your mind today?",
    },
  ];
  type Invitation = (typeof invitations)[number];
  // Retain only the newest five due invitations; older ones cannot refill the list.
  const retained = invitations
    .filter((item) => item.hoursAgo >= 0)
    .sort((a, b) => a.hoursAgo - b.hoursAgo)
    .slice(0, 5);
  let pending = $state([...retained]);
  const visible = $derived([...pending].sort((a, b) => a.hoursAgo - b.hoursAgo));
  let selected = $state<Invitation>();
  let open = $state(false);
  let draft = $state("");
  let replies = $state<string[]>([]);

  function start(item: Invitation) {
    selected = item;
    draft = "";
    replies = [];
    pending = pending.filter((entry) => entry.id !== item.id);
    open = false;
  }

  function reset(empty = false) {
    pending = empty ? [] : [...retained];
    selected = undefined;
    open = false;
  }

  // Each mounted header starts settled; only updates to its existing count animate.
  function animateCount(node: HTMLElement, count: number) {
    let previous = count;
    let animation: Animation | undefined;
    node.textContent = count ? String(count) : "";

    return {
      update(next: number) {
        if (next === previous) return;
        animation?.cancel();
        if (next > 0) {
          node.textContent = String(next);
          if (previous > 0 && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            const styles = getComputedStyle(node);
            const duration = styles.getPropertyValue("--motion-fast").trim();
            const milliseconds = parseFloat(duration) * (duration.endsWith("ms") ? 1 : 1000);
            if (milliseconds > 0) {
              animation = node.animate(
                [
                  { opacity: 0, transform: "translateY(var(--spacing-n4))" },
                  { opacity: 1, transform: "translateY(0)" },
                ],
                {
                  duration: milliseconds,
                  easing: styles.getPropertyValue("--motion-easing-smooth").trim(),
                },
              );
            }
          }
        }
        previous = next;
      },
      destroy() {
        animation?.cancel();
      },
    };
  }

  useStageControls(() => controls);
</script>

{#snippet controls()}
  <div class="demo-controls">
    <Button label="Reset messages" size="small" variant="secondary" onclick={() => reset()} />
    <Button label="Empty state" size="small" variant="secondary" onclick={() => reset(true)} />
  </div>
{/snippet}

{#snippet avatar()}
  <div class="avatar-anchor">
    <BrandAvatar
      emoji="🪶"
      label={visible.length ? `Agent, ${visible.length} waiting messages` : "Agent messages"}
      onclick={() => (open = true)}
    >
      <Icon name="brand/avatar" size="fill" />
    </BrandAvatar>
    <span class="badge" class:empty={visible.length === 0} aria-hidden="true">
      <span class="t-miniLabel" use:animateCount={visible.length}></span>
    </span>
  </div>
{/snippet}

<div class="exploration">
  <div class="underlay" inert={open}>
    {#if selected}
      <SoftEdgeScroll>
        {#snippet header()}
          <NavigationHeader>
            {#snippet leading()}
              <ActionButton
                icon="functional/note"
                label="Back to chats"
                variant="open"
                size="medium"
                onclick={() => (selected = undefined)}
              />
            {/snippet}
            {#snippet center()}{@render avatar()}{/snippet}
            {#snippet trailing()}
              <ActionButton icon="functional/phone" variant="open" size="medium" label="Call" />
            {/snippet}
          </NavigationHeader>
        {/snippet}
        <ChatFeed>
          <ChatBrandMessage><Markdown text={selected.reply} /></ChatBrandMessage>
          {#each replies as reply, index (index)}
            <ChatUserMessage text={reply} />
          {/each}
        </ChatFeed>
        {#snippet footer()}
          <ChatInput
            bind:value={draft}
            isSendEnabled={draft.trim().length > 0}
            onActionTap={() => {
              if (!draft.trim()) return;
              replies = [...replies, draft.trim()];
              draft = "";
            }}
          />
        {/snippet}
      </SoftEdgeScroll>
    {:else}
      <ChatListScreen {avatar} />
    {/if}
  </div>

  <Sheet
    bind:open
    title="For you"
    description={visible.length ? "A few things we can pick up when you’re ready." : undefined}
  >
    {#snippet primary()}
      <div class="messages">
        {#each visible as item (item.id)}
          <article class="invitation">
            <button class="card-open" onclick={() => start(item)}>
              <span class="t-tag time">{item.time}</span>
              <span class="t-titleXS">{item.message}</span>
            </button>
            <button
              class="card-dismiss"
              aria-label={`Skip ${item.context.toLowerCase()} this time`}
              onclick={() => {
                pending = pending.filter((entry) => entry.id !== item.id);
              }}><Icon name="functional/x" size={16} /></button
            >
          </article>
        {:else}
          <EmptyState
            icon="functional/sparkles"
            title="All caught up"
            description="When it’s time for something we’ve planned, you’ll find it here."
          />
        {/each}
      </div>
    {/snippet}
  </Sheet>
</div>

<style>
  .exploration {
    position: relative;
    height: 100%;
    background: var(--color-surface-standard-base);
    overflow: hidden;
  }
  .underlay {
    height: 100%;
  }
  .avatar-anchor {
    position: relative;
  }
  .badge {
    position: absolute;
    top: calc(-1 * var(--spacing-n2));
    right: calc(-1 * var(--spacing-n8));
    min-width: var(--spacing-n20);
    height: var(--spacing-n20);
    padding: 0 var(--spacing-n4);
    box-sizing: border-box;
    display: grid;
    place-items: center;
    border-radius: var(--radius-full);
    background: var(--color-text-standard-base);
    color: var(--color-surface-standard-base);
    pointer-events: none;
    transform-origin: center;
    transition:
      opacity var(--motion-fast) var(--motion-easing-smooth),
      transform var(--motion-fast) var(--motion-easing-smooth);
  }
  .badge.empty {
    opacity: 0;
    transform: scale(0.8);
  }
  @media (prefers-reduced-motion: reduce) {
    .badge {
      transition-duration: 0s;
    }
  }
  .messages {
    padding: 0 var(--spacing-n24);
  }
  .invitation {
    position: relative;
    background: var(--color-surface-standard-elevated);
    border-radius: var(--radius-card);
    margin-bottom: var(--spacing-n12);
  }
  .card-open {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n12);
    width: 100%;
    padding: var(--spacing-n24) var(--spacing-n40) var(--spacing-n24) var(--spacing-n20);
    border: 0;
    border-radius: inherit;
    background: transparent;
    color: var(--color-text-standard-base);
    text-align: left;
    cursor: pointer;
  }
  .card-open:hover {
    background: color-mix(in srgb, var(--color-text-standard-base) 4%, transparent);
  }
  .card-dismiss {
    position: absolute;
    top: var(--spacing-n4);
    right: var(--spacing-n4);
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    padding: 0;
    border: 0;
    border-radius: 50%;
    background: transparent;
    color: var(--color-text-standard-muted);
    cursor: pointer;
  }
  .card-open:focus-visible,
  .card-dismiss:focus-visible {
    outline: 2px solid var(--color-text-standard-base);
    outline-offset: 2px;
  }
  .time {
    color: var(--color-text-standard-muted);
  }
  .demo-controls {
    display: flex;
    gap: var(--spacing-n8);
  }
</style>
