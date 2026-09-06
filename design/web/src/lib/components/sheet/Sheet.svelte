<script lang="ts">
  import { untrack, type Snippet } from "svelte";
  import SheetHeader from "./SheetHeader.svelte";

  interface Props {
    /** Two-way bindable presentation state. */
    open?: boolean;
    title: string;
    label?: string;
    description?: string;
    descriptionContent?: Snippet;
    /** Shows the header close button. */
    showsDismissButton?: boolean;
    /**
     * Draws the sheet's own grabber and header. A page presented modally —
     * The plain `.sheet` presentation, not `appSheet` — brings its own chrome,
     * so it turns this off and fills the slot itself.
     */
    chrome?: boolean;
    /** Takes all the room the cap allows, rather than hugging its content. */
    fills?: boolean;
    onDismiss?: () => void;
    primary: Snippet;
    secondary?: Snippet;
  }

  let {
    open = $bindable(false),
    title,
    label,
    description,
    descriptionContent,
    showsDismissButton = true,
    chrome = true,
    fills = false,
    onDismiss,
    primary,
    secondary,
  }: Props = $props();

  /* Mounted from first presentation until the leave transition ends, so
     closing can animate. */
  let mounted = $state(false);
  let visible = $state(false);

  let sheet = $state<HTMLDivElement>();
  let returnFocus: HTMLElement | null = null;
  let leaveTimer: ReturnType<typeof setTimeout> | undefined;
  /* Bumped on every present/leave so a queued frame from a superseded
     transition cannot revive or kill the current one. */
  let generation = 0;

  function dismiss() {
    open = false;
    onDismiss?.();
  }

  /*
   * Only `open` is a dependency. The rest runs untracked: presenting and
   * leaving read the state they manage, and a tracked read would re-enter this
   * effect the moment they wrote to it — which tore the sheet down mid-exit
   * instead of animating it away.
   */
  $effect(() => {
    const isOpen = open;
    untrack(() => {
      if (isOpen) present();
      else if (mounted) leave();
    });
  });

  function present() {
    clearTimeout(leaveTimer);
    const token = ++generation;
    if (!mounted) returnFocus = document.activeElement as HTMLElement | null;
    mounted = true;
    // The transition starts a frame later, once the open dialog has been laid
    // out at its offscreen position.
    requestAnimationFrame(() => {
      if (token !== generation || !sheet) return;
      // Focusing must not scroll the page the sheet is presented over.
      sheet.focus({ preventScroll: true });
      requestAnimationFrame(() => {
        if (token === generation) visible = true;
      });
    });
  }

  function leave() {
    generation += 1;
    if (!visible) {
      teardown();
      return;
    }
    visible = false;
    // Safety net in case transitionend never fires (e.g. zero-duration motion).
    clearTimeout(leaveTimer);
    leaveTimer = setTimeout(teardown, 600);
  }

  function teardown() {
    clearTimeout(leaveTimer);
    returnFocus?.focus({ preventScroll: true });
    returnFocus = null;
    visible = false;
    mounted = false;
  }

  /* Escape closes, like a native sheet's swipe or backdrop tap. */
  $effect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") dismiss();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  });
</script>

<!--
  A bottom sheet with a header block and scrollable
  content. Anchors to the nearest positioned ancestor, so a phone frame or
  screen root can confine it; give that ancestor `position: relative`.

  Deliberately not a `<dialog>`: the sheet must stay inside its frame rather
  than the top layer, so focus, Escape and the backdrop are handled here
  anyway — and a shown non-modal dialog mispositions mid-transition in WebKit,
  swooping past the top of the frame before snapping back.

  Divergence from iOS: the drag indicator is drawn but sheets are not
  draggable — dismissal is the close button, Escape or a backdrop tap.
-->
{#if mounted}
  <div class="layer">
    <div class="backdrop" class:visible onclick={dismiss} aria-hidden="true"></div>
    <div
      bind:this={sheet}
      class="sheet"
      class:visible
      class:fills
      class:bare={!chrome}
      role="dialog"
      aria-modal="true"
      aria-labelledby="title"
      tabindex="-1"
      ontransitionend={(event) => {
        if (
          event.propertyName === "transform" &&
          event.target === event.currentTarget &&
          !visible
        ) {
          teardown();
        }
      }}
    >
      {#if chrome}
        <div class="grabber" aria-hidden="true"></div>
        <SheetHeader
          {title}
          {label}
          {description}
          {descriptionContent}
          onDismiss={showsDismissButton ? dismiss : undefined}
        />
        <div class="content">
          <div class="stack">
            {@render primary()}
            {#if secondary}
              {@render secondary()}
            {/if}
          </div>
        </div>
      {:else}
        {@render primary()}
      {/if}
    </div>
  </div>
{/if}

<style>
  .layer {
    position: absolute;
    inset: 0;
  }

  .backdrop {
    position: absolute;
    inset: 0;
    background: rgb(0 0 0 / 40%);
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-gentle);
  }

  .backdrop.visible {
    opacity: 1;
  }

  .sheet {
    position: absolute;
    top: auto;
    bottom: 0;
    left: 0;
    right: 0;
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
    width: 100%;
    margin: 0;
    padding: var(--spacing-n32) 0 0;
    border: none;
    border-radius: var(--radius-card) var(--radius-card) 0 0;
    background: var(--color-surface-standard-base);
    transform: translateY(100%);
    transition: transform var(--motion-normal) var(--motion-easing-gentle);
  }

  /* A sheet is as tall as what it holds, and no taller than the room above it:
     it stops below the container's top safe area rather than reaching for a
     detent. Content past that scrolls inside. iOS picks from a detent set;
     content on the web already flows, so the size follows it. */
  .sheet {
    max-height: calc(100% - var(--eigin-safe-area-top, 0px) - var(--spacing-n32));
  }

  /* A page presented modally takes the room rather than hugging: its content
     is a screen, and a form that resized as you typed would be unusable. */
  .sheet.fills {
    height: calc(100% - var(--eigin-safe-area-top, 0px) - var(--spacing-n32));
  }

  /* Its own header sits at the very top, so there is no chrome to pad for. */
  .sheet.bare {
    padding-top: 0;
    overflow: hidden;
  }

  .sheet.visible {
    transform: translateY(0);
  }

  .sheet:focus {
    outline: none;
  }

  /* The iOS drag indicator, drawn since the sheet itself cannot be dragged. */
  .grabber {
    position: absolute;
    top: var(--spacing-n8);
    left: 50%;
    width: 36px;
    height: 5px;
    border-radius: 999px;
    background: color-mix(in srgb, var(--color-border-standard-base) 60%, transparent);
    transform: translateX(-50%);
  }

  .content {
    overflow-y: auto;
    /* VStack(spacing: pyTop) between header and scroll area on iOS. */
    margin-top: var(--spacing-n32);
  }

  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding-bottom: var(--spacing-n40);
  }
</style>
