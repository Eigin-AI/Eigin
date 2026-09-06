<script lang="ts">
  /* Mirrors AppChatUserMessage: long messages render collapsed and expand on
     tap. Thresholds, in characters and points. */
  const COLLAPSE_THRESHOLD = 200;
  const COLLAPSED_HEIGHT = 110;

  interface Props {
    text: string;
  }

  const { text }: Props = $props();

  const isLong = $derived(text.length > COLLAPSE_THRESHOLD);
  let collapsed = $state(true);
  const isCollapsed = $derived(isLong && collapsed);

  /* Expanding needs a concrete target height, since max-height can't animate
     to auto. Tracked live so reflows and font swaps stay correct. */
  let body = $state<HTMLElement | undefined>();
  let fullHeight = $state(0);

  $effect(() => {
    if (!body) return;
    const observer = new ResizeObserver(() => {
      if (body) fullHeight = body.scrollHeight;
    });
    observer.observe(body);
    return () => observer.disconnect();
  });

  const maxHeight = $derived(
    isCollapsed ? `${COLLAPSED_HEIGHT}px` : fullHeight ? `${fullHeight}px` : "none",
  );
</script>

<div class="row">
  <svelte:element
    this={isLong ? "button" : "div"}
    class="bubble"
    class:long={isLong}
    class:collapsed={isCollapsed}
    type={isLong ? "button" : undefined}
    aria-expanded={isLong ? !collapsed : undefined}
    onclick={isLong ? () => (collapsed = !collapsed) : undefined}
    role={isLong ? "button" : undefined}
    tabindex={isLong ? 0 : undefined}
  >
    <div class="body t-chatMessageUser" bind:this={body} style:max-height={maxHeight}>
      {text}
    </div>
  </svelte:element>
</div>

<style>
  .row {
    display: flex;
    justify-content: flex-end;
    box-sizing: border-box;
    width: 100%;
    padding-left: var(--chat-px-large);
    padding-right: var(--chat-px-small);
  }

  .bubble {
    box-sizing: border-box;
    padding: var(--spacing-n24);
    border: none;
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-alternative);
    color: var(--color-text-standard-base);
    text-align: left;
    font: inherit;
  }

  /* Short messages hug their text; long ones fill the column. */
  .bubble.long {
    width: 100%;
    cursor: pointer;
  }

  /*
   * The bubble pads against an untrimmed line box, so keep the natural
   * one here. Trimming it would both tighten the padding and, with the
   * clipping the collapse needs, shave ascenders and descenders off the text.
   */
  .body {
    text-box: normal;
    overflow: hidden;
    user-select: text;
    white-space: pre-wrap;
    transition: max-height var(--motion-slow) var(--motion-easing-gentle);
  }

  /* The collapsed bubble fades out over a 28pt mask. */
  .bubble.collapsed .body {
    mask-image: linear-gradient(to bottom, black calc(100% - 28px), transparent 100%);
  }
</style>
