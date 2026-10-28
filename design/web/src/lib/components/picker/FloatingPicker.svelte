<script lang="ts">
  import { onMount, tick, type Snippet } from "svelte";
  import { autoUpdate, computePosition, flip, offset, shift } from "@floating-ui/dom";
  import Icon from "../icon/Icon.svelte";
  import { scaleGroups } from "../../generated/tokens";
  import "../button/button.css";

  const spacing = scaleGroups.find((group) => group.name === "spacing")!.tokens;
  const triggerGap = spacing.find((token) => token.name === "n8")!.value;
  const viewportPadding = spacing.find((token) => token.name === "n12")!.value;
  const defaultRowGap = spacing.find((token) => token.name === "n16")!.value;

  let {
    label,
    trigger,
    children,
    rowGap = defaultRowGap,
    side = "bottom",
    iconOnly = false,
  }: {
    /** Accessible label for the trigger. */
    label: string;
    /** Preferred opening side; flips when space is limited. */
    side?: "top" | "bottom";
    /** Circular secondary button without a disclosure indicator. */
    iconOnly?: boolean;
    /** Space between supplied rows in pixels. */
    rowGap?: number;
    /** Compact content shown beside the disclosure indicator. */
    trigger: Snippet;
    /** Floating rows; call dismiss after choosing an item. */
    children: Snippet<[dismiss: () => void]>;
  } = $props();

  let root = $state<HTMLElement>();
  let fallback = $state<HTMLDetailsElement>();
  let summary = $state<HTMLElement>();
  let panel = $state<HTMLElement>();
  let content = $state<HTMLElement>();
  let reveal = $state<HTMLElement>();
  let enhanced = $state(false);
  let open = $state(false);
  let present = $state(false);
  let positioned = $state(false);
  let expanded = $state(false);
  let placement = $state("bottom-start");
  let closingId = 0;

  onMount(() => {
    if ("showPopover" in HTMLElement.prototype) {
      // Preserve a native disclosure opened before hydration completes.
      open = fallback?.open ?? false;
      enhanced = true;
    }
  });

  $effect(() => {
    const version = ++closingId;
    if (open) {
      present = true;
      if (positioned) expanded = true;
    } else if (present) {
      expanded = false;
      // Keep the surface mounted until its contraction and fade have finished.
      void tick().then(async () => {
        await Promise.allSettled(
          reveal?.getAnimations({ subtree: true }).map((animation) => animation.finished) ?? [],
        );
        if (!open && version === closingId) present = false;
      });
    }
  });

  $effect(() => {
    if (!enhanced || !present || !summary || !panel || !content) return;
    const reference = summary;
    const floating = panel;
    const body = content;
    let active = true;
    floating.showPopover();

    const update = () => {
      // Position the full surface so its side stays stable throughout the reveal.
      floating.style.height = `${body.getBoundingClientRect().height}px`;
      void computePosition(reference, floating, {
        placement: `${side}-start`,
        strategy: "fixed",
        middleware: [
          offset(triggerGap),
          flip({ padding: viewportPadding, altBoundary: true }),
          shift({ padding: viewportPadding, altBoundary: true }),
        ],
      }).then(({ x, y, placement: nextPlacement }) => {
        if (!active) return;
        Object.assign(floating.style, { left: `${x}px`, top: `${y}px` });
        placement = nextPlacement;
        positioned = true;
      });
    };
    const cleanup = autoUpdate(reference, floating, update);
    const observer = new ResizeObserver(update);
    observer.observe(body);
    return () => {
      active = false;
      observer.disconnect();
      cleanup();
      floating.hidePopover();
      positioned = false;
    };
  });

  function dismiss() {
    // Selection removes the surface before the chosen content changes.
    ++closingId;
    if (fallback) fallback.open = false;
    open = false;
    expanded = false;
    present = false;
    summary?.focus();
  }

  function close() {
    open = false;
    summary?.focus();
  }
  function toggle(event: MouseEvent) {
    if (!enhanced) return;
    event.preventDefault();
    open = !open;
  }
  function dismissOutside(event: Event) {
    if (open && event.target instanceof Node && !root?.contains(event.target)) open = false;
  }
  function onkeydown(event: KeyboardEvent) {
    if (open && event.key === "Escape") {
      event.preventDefault();
      close();
      summary?.focus();
    }
  }
</script>

<svelte:window onpointerdown={dismissOutside} onfocusin={dismissOutside} {onkeydown} />

{#snippet triggerContent()}
  {@render trigger()}
  {#if !iconOnly}<span class="chevron" class:show-up={open} aria-hidden="true">
      <span class="chevron-down"><Icon name="functional/chevron/down" size={12} /></span>
      <span class="chevron-up"><Icon name="functional/chevron/up" size={12} /></span>
    </span>{/if}
{/snippet}

{#snippet floatingContent()}
  <div
    class="picker-panel"
    bind:this={panel}
    popover={enhanced ? "manual" : undefined}
    data-positioned={positioned ? "" : undefined}
    data-placement={placement}
    inert={enhanced && !open}
  >
    <div class="reveal" class:expanded bind:this={reveal}>
      <div class="clip">
        <div class="panel-content" style:gap="{rowGap}px" bind:this={content}>
          {@render children(dismiss)}
        </div>
      </div>
    </div>
  </div>
{/snippet}

<div class="floating-picker" class:enhanced data-side={side} bind:this={root}>
  {#if enhanced}
    <button
      type="button"
      class={iconOnly ? "picker-trigger eigin-btn action secondary extraSmall" : "picker-trigger"}
      title={iconOnly ? label : undefined}
      bind:this={summary}
      aria-label={label}
      aria-expanded={open}
      onclick={toggle}
    >
      {@render triggerContent()}
    </button>
    {#if present}{@render floatingContent()}{/if}
  {:else}
    <details bind:this={fallback}>
      <summary
        class={iconOnly ? "picker-trigger eigin-btn action secondary extraSmall" : "picker-trigger"}
        aria-label={label}
        title={iconOnly ? label : undefined}>{@render triggerContent()}</summary
      >
      {@render floatingContent()}
    </details>
  {/if}
</div>

<style>
  .floating-picker {
    position: relative;
    width: fit-content;
  }
  .picker-trigger {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-n8);
    min-width: 64px;
    min-height: 44px;
    padding: 0 var(--spacing-n12);
    border-radius: var(--radius-full);
    color: var(--color-text-standard-base);
    list-style: none;
    border: none;
    background: transparent;
    font-family: inherit;
    cursor: pointer;
    -webkit-user-select: none;
    user-select: none;
  }
  .picker-trigger.eigin-btn {
    min-width: var(--btn-action-size);
    min-height: var(--btn-action-size);
    padding: 0;
    background: var(--btn-bg);
    color: var(--btn-fg);
  }
  .floating-picker[data-side="top"] .picker-panel:not([popover]) {
    top: auto;
    bottom: calc(100% + var(--spacing-n8));
  }
  .picker-trigger::-webkit-details-marker {
    display: none;
  }
  .picker-trigger:not(.eigin-btn):hover {
    background: var(--color-interaction-light-hover);
  }
  .picker-trigger:focus-visible {
    outline: 2px solid var(--color-interaction-border-focus);
    outline-offset: 2px;
  }
  .chevron {
    display: grid;
  }
  .chevron-down,
  .chevron-up {
    display: inline-flex;
    grid-area: 1 / 1;
    transition: opacity var(--motion-fast) var(--motion-easing-smooth);
  }
  .chevron-up {
    opacity: 0;
  }
  .chevron.show-up .chevron-down {
    opacity: 0;
  }
  .chevron.show-up .chevron-up {
    opacity: 1;
  }
  .picker-panel {
    position: absolute;
    z-index: 20;
    right: 0;
    top: calc(100% + var(--spacing-n8));
    display: grid;
    align-content: start;
    width: max-content;
    min-width: min(180px, calc(100vw - 32px));
    max-width: min(420px, calc(100vw - 32px));
    margin: 0;
    padding: 0;
    border: none;
    background: transparent;
    color: var(--color-text-standard-base);
  }
  .picker-panel[popover] {
    position: fixed;
    inset: auto;
    /* Browsers default popovers to overflow: auto, which would clip the shadow. */
    overflow: visible;
    visibility: hidden;
  }
  .picker-panel[data-positioned] {
    visibility: visible;
  }
  .reveal {
    display: grid;
    grid-template-rows: 1fr;
    width: 100%;
    overflow: hidden;
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-alternative);
    box-shadow: 0 var(--spacing-n4) var(--spacing-n16)
      color-mix(in srgb, var(--color-button-impact-primary) 16%, transparent);
  }
  .clip {
    min-height: 0;
    overflow: hidden;
  }
  .panel-content {
    display: grid;
    gap: var(--spacing-n16);
    padding: var(--spacing-n24);
  }
  .enhanced .reveal {
    grid-template-rows: 0fr;
    opacity: 0;
    transition:
      grid-template-rows var(--motion-normal) var(--motion-easing-smooth),
      opacity var(--motion-normal) var(--motion-easing-smooth);
  }
  .enhanced .reveal.expanded {
    grid-template-rows: 1fr;
    opacity: 1;
  }
  .picker-panel[data-placement^="top"] {
    align-content: end;
  }
  @media (prefers-reduced-motion: reduce) {
    .enhanced .reveal,
    .chevron-down,
    .chevron-up {
      transition: none;
    }
  }
</style>
