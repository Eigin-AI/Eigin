<script lang="ts">
  import ActionButton from "../button/ActionButton.svelte";
  import type { MicState } from "./types";

  let {
    value = $bindable(""),
    placeholder = "Chat with Eigin",
    isSendEnabled = false,
    showStopButton = false,
    micState = "idle",
    overlayText,
    onSend,
    onStop,
    onMicTap,
    onActionTap,
  }: {
    value?: string;
    placeholder?: string;
    isSendEnabled?: boolean;
    showStopButton?: boolean;
    /** Mirrors `AppChatInput.MicState`. */
    micState?: MicState;
    /** Replaces the collapsed text, e.g. live transcription. */
    overlayText?: string;
    onSend?: () => void;
    onStop?: () => void;
    onMicTap?: () => void;
    /** Omit to hide the leading action button, as on iOS. */
    onActionTap?: () => void;
  } = $props();

  /* Focus drives both visual states: the box expands into a card and the
     inline buttons move down into a footer row. Both rows stay mounted so
     their size contributions can animate instead of snapping.

     Only the text field opens it — tapping a button or the bar's background
     leaves it alone — and only sending or clicking away closes it. */
  let expanded = $state(false);
  let field = $state<HTMLTextAreaElement>();
  let root = $state<HTMLElement>();

  function collapse() {
    expanded = false;
    field?.blur();
  }

  function send() {
    onSend?.();
    collapse();
  }

  /* Clicking outside the whole component closes it; clicks inside don't. */
  $effect(() => {
    if (!expanded) return;
    const onPointerDown = (event: PointerEvent) => {
      if (root && !root.contains(event.target as Node)) collapse();
    };
    document.addEventListener("pointerdown", onPointerDown, true);
    return () => document.removeEventListener("pointerdown", onPointerDown, true);
  });

  const collapsedText = $derived(overlayText ?? value);

  /* Grows with content, up to 10 lines, while open. Collapsed it is one line:
     the field sits invisibly in the pill, so its height is the pill's. Tracks
     the value, so text set from outside resizes it too. */
  $effect(() => {
    void value;
    if (!field) return;
    const line = Number.parseFloat(getComputedStyle(field).lineHeight);
    field.style.height = "auto";
    field.style.height = expanded ? `${Math.min(field.scrollHeight, line * 10)}px` : `${line}px`;
  });
</script>

<!--
  A chat composer. Inactive: a single-row pill with compact inline
  buttons. Active: a card whose bottom corners square off, with the buttons
  moved to a footer row.
-->
<div class="outer" class:expanded bind:this={root}>
  <div class="box" class:expanded>
    <div class="row">
      <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
      <div class="text-area" onclick={() => field?.focus()}>
        <textarea
          bind:this={field}
          bind:value
          rows="1"
          class="t-chatMessageUser"
          class:visible={expanded}
          {placeholder}
          onfocus={() => (expanded = true)}
        ></textarea>

        <span
          class="collapsed t-chatMessageUser"
          class:hidden={expanded}
          class:muted={collapsedText.length === 0}
          class:head={micState === "active"}
        >
          <span>{collapsedText.length === 0 ? placeholder : collapsedText}</span>
        </span>
      </div>

      <!-- Stays mounted; its width animates to zero so the field grows into
           the space instead of the text snapping wider. -->
      <div class="inline" class:hidden={expanded} inert={expanded}>
        {#if onActionTap}
          <ActionButton
            icon="functional/plus"
            variant="secondary"
            size="extraSmall"
            onclick={onActionTap}
          />
        {/if}
        <span class="mic" class:pulsing={micState === "active"}>
          <ActionButton
            icon="functional/microphone"
            variant={micState === "active" ? "spot" : "secondary"}
            size="extraSmall"
            onclick={onMicTap}
          />
        </span>
        <ActionButton
          icon={showStopButton ? "brand/pause" : "functional/arrow/up"}
          variant="primary"
          size="medium"
          disabled={!showStopButton && !isSendEnabled}
          onclick={showStopButton ? onStop : send}
        />
      </div>
    </div>

    <!-- Footer moves in from the bottom edge with opacity. The grid row
         animates from 0fr to 1fr so the card grows smoothly with it. -->
    <div class="footer-wrap" class:open={expanded}>
      <div class="footer" inert={!expanded}>
        {#if onActionTap}
          <ActionButton
            icon="functional/plus"
            variant="secondary"
            size="extraSmall"
            onclick={onActionTap}
          />
        {/if}
        <span class="spacer"></span>
        <span class="mic" class:pulsing={micState === "active"}>
          <ActionButton
            icon="functional/microphone"
            variant={micState === "active" ? "spot" : "secondary"}
            size="extraSmall"
            onclick={onMicTap}
          />
        </span>
        <ActionButton
          icon={showStopButton ? "brand/pause" : "functional/arrow/up"}
          variant="primary"
          size="extraSmall"
          disabled={!showStopButton && !isSendEnabled}
          onclick={showStopButton ? onStop : send}
        />
      </div>
    </div>
  </div>
</div>

<style>
  .outer {
    /* Horizontal inset only while collapsed. */
    padding: 0 var(--spacing-n8);
    transition: padding var(--motion-normal) var(--motion-easing-smooth);
  }

  .outer.expanded {
    padding: 0;
  }

  .box {
    /* Staged transition: buttons fade out, the bar reshapes, the new buttons
       fade in. Stage two waits for the fade, stage three for the reshape. */
    --stage-reshape: var(--motion-fast);
    --stage-fade-in: calc(var(--motion-fast) + var(--motion-normal));

    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    min-height: var(--sizing-button-action-medium);
    padding: var(--spacing-n8) var(--sizing-input-px-right) var(--spacing-n8)
      var(--sizing-input-px-left);
    background: var(--color-surface-standard-elevated);
    /* Collapsed: pill. Expanded: card corners on top, square at the bottom. */
    border-radius: 100px;
    cursor: text;
    transition:
      border-radius var(--motion-normal) var(--motion-easing-smooth) var(--stage-reshape),
      padding var(--motion-normal) var(--motion-easing-smooth) var(--stage-reshape);
  }

  .box.expanded {
    padding: var(--spacing-n24) var(--spacing-n16) var(--spacing-n24) var(--spacing-n32);
    border-radius: var(--radius-card) var(--radius-card) 0 0;
  }

  .row {
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
    /* Collapsed the row is as tall as the medium send button; expanded it
       shrinks to the text. Animating it stops the text from jumping. */
    min-height: var(--sizing-button-action-medium);
    transition: min-height var(--motion-normal) var(--motion-easing-smooth) var(--stage-reshape);
  }

  .box.expanded .row {
    min-height: var(--sizing-button-action-extraSmall);
  }

  .text-area {
    position: relative;
    flex: 1;
    min-width: 0;
    display: flex;
  }

  textarea {
    width: 100%;
    border: none;
    background: transparent;
    padding: 0;
    margin: 0;
    resize: none;
    color: var(--color-text-standard-base);
    font-family: inherit;
    overflow-y: auto;
    scrollbar-width: none;
    opacity: 0;
    pointer-events: none;
    /* Stage three: the field appears once the bar has reshaped. */
    transition: opacity var(--motion-fast) var(--motion-easing-snap) var(--stage-fade-in);
  }

  textarea.visible {
    opacity: 1;
    pointer-events: auto;
  }

  textarea:focus {
    outline: none;
  }

  textarea::placeholder {
    color: var(--color-text-standard-muted);
  }

  /* Collapsed row shows a single truncated line instead of the field.
     Flex-centred because a trimmed text box doesn't fill the stretched box. */
  .collapsed {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    color: var(--color-text-standard-base);
    white-space: nowrap;
    overflow: hidden;
    pointer-events: none;
    opacity: 1;
    /* Stage three coming back, stage one going out. */
    transition: opacity var(--motion-fast) var(--motion-easing-snap) var(--stage-fade-in);
  }

  .collapsed.hidden {
    opacity: 0;
    transition: opacity var(--motion-fast) var(--motion-easing-snap) 0ms;
  }

  .collapsed > span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
  }

  .collapsed.muted {
    color: var(--color-text-standard-muted);
  }

  /* Dictation truncates from the head, so the tail stays visible. */
  .collapsed.head {
    direction: rtl;
    text-align: left;
  }

  /* Stage three on the way back: width grows with the bar, label fades in
     only once the reshape has finished. */
  .inline {
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
    flex: none;
    overflow: hidden;
    max-width: 240px;
    opacity: 1;
    transition:
      max-width var(--motion-normal) var(--motion-easing-smooth) var(--stage-reshape),
      opacity var(--motion-fast) var(--motion-easing-snap) var(--stage-fade-in);
  }

  /* Stage one on the way out: fade first, then let the width collapse. */
  .inline.hidden {
    max-width: 0;
    opacity: 0;
    pointer-events: none;
    transition:
      max-width var(--motion-normal) var(--motion-easing-smooth) var(--stage-reshape),
      opacity var(--motion-fast) var(--motion-easing-snap) 0ms;
  }

  /* Footer height animates from 0fr to 1fr, so the card grows with it. */
  .footer-wrap {
    display: grid;
    grid-template-rows: 0fr;
    transition: grid-template-rows var(--motion-normal) var(--motion-easing-smooth)
      var(--stage-reshape);
  }

  .footer-wrap.open {
    grid-template-rows: 1fr;
  }

  /* Stage one on the way out: fade immediately. */
  .footer {
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
    min-height: 0;
    overflow: hidden;
    opacity: 0;
    transition: opacity var(--motion-fast) var(--motion-easing-snap) 0ms;
  }

  /* Stage three on the way in: fade once the bar has finished reshaping. */
  .footer-wrap.open .footer {
    opacity: 1;
    transition: opacity var(--motion-fast) var(--motion-easing-snap) var(--stage-fade-in);
    /* n8 between the field and the footer. */
    padding-top: var(--spacing-n8);
  }

  .spacer {
    flex: 1;
  }

  .mic {
    display: inline-flex;
  }

  .mic.pulsing {
    animation: pulse 1.4s ease-in-out infinite;
  }

  @keyframes pulse {
    0%,
    100% {
      transform: scale(1);
      opacity: 1;
    }
    50% {
      transform: scale(1.08);
      opacity: 0.85;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .mic.pulsing {
      animation: none;
    }
  }
</style>
