<script lang="ts">
  import { untrack } from "svelte";
  import { ActionButton, CardSurface, Icon, ChatInput, ChatUserMessage } from "@eigin/ui";
  import type { ChatExample, ChatLabels } from "../../content/home/types";
  import AgentBlob from "./AgentBlob.svelte";
  import { blobPose, frame, timeline } from "./timeline";

  /** A conceptual exchange, paused off-screen and readable without animation. */
  let {
    examples,
    labels,
    index = $bindable(0),
    id,
  }: { examples: ChatExample[]; labels: ChatLabels; index?: number; id?: string } = $props();

  const example = $derived(examples[index]);
  const line = $derived(timeline(example));
  let elapsed = $state(0);
  let mounted = $state(false);
  let inView = $state(false);
  let pageVisible = $state(true);
  let reduced = $state(false);
  let paused = $state(false);
  let screen: HTMLElement;
  let askHeight = $state(64);
  let screenWidth = $state(500);
  let screenHeight = $state(440);
  let turnHeight = $state(360);
  const running = $derived(mounted && inView && pageVisible && !reduced && !paused);
  const time = $derived(!mounted || reduced ? line.leave - 1 : elapsed);
  const now = $derived(frame(example, line, time));
  const pose = $derived(
    blobPose(
      line,
      time,
      screenWidth,
      screenHeight,
      (screenHeight - turnHeight) / 2 + askHeight + 44,
    ),
  );

  $effect.pre(() => {
    void index;
    elapsed = untrack(() => (paused ? line.leave - 1 : 0));
  });

  $effect(() => {
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    const updateMotion = () => (reduced = motion.matches);
    const updateVisibility = () => (pageVisible = !document.hidden);
    updateMotion();
    updateVisibility();
    mounted = true;
    motion.addEventListener("change", updateMotion);
    document.addEventListener("visibilitychange", updateVisibility);
    const observer = new IntersectionObserver(
      ([entry]) => {
        inView = entry.isIntersecting && entry.intersectionRatio >= 0.15;
      },
      { threshold: [0, 0.15] },
    );
    observer.observe(screen);
    return () => {
      motion.removeEventListener("change", updateMotion);
      document.removeEventListener("visibilitychange", updateVisibility);
      observer.disconnect();
    };
  });

  $effect(() => {
    if (!running) return;
    let last = performance.now();
    let frameId = requestAnimationFrame(function step(time) {
      elapsed += Math.min(time - last, 100);
      last = time;
      if (elapsed >= line.end) {
        index = (index + 1) % examples.length;
        elapsed = 0;
      }
      frameId = requestAnimationFrame(step);
    });
    return () => cancelAnimationFrame(frameId);
  });
</script>

{#snippet actionCard(headline: string, description: string, symbol: import("@eigin/ui").IconName)}
  <CardSurface>
    <div class="chat-action-row">
      <Icon name={symbol} size={24} />
      <div class="chat-action-copy">
        <span class="t-titleXS">{headline}</span>
        <span class="t-body">{description}</span>
      </div>
      <span class="chat-action-arrow"><Icon name="functional/arrow/right" size={16} /></span>
    </div>
  </CardSurface>
{/snippet}

<div class="chat-stage" {id} role="region" aria-label={labels.examples}>
  <div
    class="chat-screen"
    data-phase={now.phase}
    data-ready={mounted || undefined}
    style:--composer={now.composer}
    style:--question={now.question}
    style:--answer={now.answer}
    style:--ending={now.ending}
    bind:clientWidth={screenWidth}
    bind:clientHeight={screenHeight}
    class:paused={!running}
    bind:this={screen}
    aria-hidden="true"
    inert
  >
    <div
      class="chat-agent"
      style:left="{pose.x}px"
      style:top="{pose.y}px"
      style:transform="translate(-50%, -50%) scale({pose.scale * pose.stretchX}, {pose.scale *
        pose.stretchY})"
    >
      <AgentBlob active={running && now.wobbling} />
    </div>
    <div class="chat-compose t-chatMessageUser" style:--chat-prompt={JSON.stringify(example.ask)}>
      <ChatInput value={now.draft} placeholder={labels.placeholder} isSendEnabled={!!now.draft} />
    </div>
    <div class="chat-turn" bind:clientHeight={turnHeight}>
      <div class="chat-ask" bind:clientHeight={askHeight}>
        <ChatUserMessage text={example.ask} />
      </div>
      <div class="chat-answer">
        <p class="chat-tool t-body" class:shown={now.phase === "thinking"}>{example.tools[0]}</p>
        <div class="chat-response">
          <p class="t-standfirst chat-reply">
            <span>{now.said}</span><span class="chat-unsaid"
              >{example.reply.slice(now.said.length)}</span
            >
          </p>
          <div class="chat-ending">
            {#if example.permission}
              {@render actionCard(
                example.permission.headline,
                example.permission.value,
                example.permission.symbol,
              )}
            {:else if example.options}
              <div class="chat-options">
                {#each example.options as option}
                  {@render actionCard(option.label, option.description, option.symbol)}
                {/each}
              </div>
            {/if}
          </div>
        </div>
      </div>
    </div>
  </div>
  <div class="chat-controls">
    {#if mounted && !reduced}
      <ActionButton
        icon={paused ? "brand/play" : "brand/pause"}
        label={paused ? labels.play : labels.pause}
        size="extraSmall"
        variant="open"
        onclick={() => (paused = !paused)}
      />
    {/if}
  </div>
  <div class="sr-only">
    <p>{example.ask}</p>
    <p>{example.reply}</p>
    {#if example.permission}<p>{labels.allow}: {example.permission.value}</p>{/if}
    {#if example.options}<p>
        {example.options.map((option) => `${option.label}. ${option.description}`).join(". ")}
      </p>{/if}
  </div>
</div>
