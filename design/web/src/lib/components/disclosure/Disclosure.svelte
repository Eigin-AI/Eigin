<script lang="ts">
  import { untrack, type Snippet } from "svelte";
  import PlusMinusIndicator from "./PlusMinusIndicator.svelte";
  import type { DisclosureVariant } from "./types";

  let {
    title,
    description,
    variant = "card",
    initiallyExpanded = false,
    children,
  }: {
    title: string;
    /** Summary of the current choice, shown under the title. */
    description?: string;
    /** `open` drops the card surface for embedding in a CardSurface. */
    variant?: DisclosureVariant;
    initiallyExpanded?: boolean;
    children: Snippet;
  } = $props();

  /* Seeds the opening state once, on mount. */
  let isExpanded = $state(untrack(() => initiallyExpanded));
</script>

<!--
  A titled row that folds out content. Only the header
  toggles, so taps inside the revealed content never collapse it.
-->
<div class="disclosure {variant}">
  <button
    type="button"
    class="header"
    aria-expanded={isExpanded}
    onclick={() => (isExpanded = !isExpanded)}
  >
    <span class="labels">
      <span class="t-titleXS title">{title}</span>
      {#if description}
        <span class="t-tag description">{description}</span>
      {/if}
    </span>
    <PlusMinusIndicator {isExpanded} />
  </button>

  <div class="reveal" class:open={isExpanded}>
    <div class="clip">
      <div class="divider"></div>
      <div class="panel">{@render children()}</div>
    </div>
  </div>
</div>

<style>
  .disclosure {
    width: 100%;
  }

  .disclosure.card {
    background: var(--color-surface-standard-alternative);
    border-radius: var(--radius-card);
    overflow: hidden;
  }

  .header {
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
    width: 100%;
    box-sizing: border-box;
    padding: var(--spacing-n16) var(--spacing-n24);
    background: transparent;
    border: none;
    font-family: inherit;
    text-align: left;
    cursor: pointer;
  }

  .labels {
    display: flex;
    flex-direction: column;
    /* n4 assumes untrimmed text boxes, which carry their own room above and
       below. Trimmed, the equivalent visual gap is ~12px. */
    gap: var(--spacing-n12);
    flex: 1;
    min-width: 0;
  }

  .title {
    color: var(--color-text-standard-base);
  }

  .description {
    color: var(--color-text-standard-muted);
  }

  /* Height animates from 0fr to 1fr so the fold-out grows smoothly. */
  .reveal {
    display: grid;
    grid-template-rows: 0fr;
    transition: grid-template-rows var(--motion-normal) var(--motion-easing-smooth);
  }

  .reveal.open {
    grid-template-rows: 1fr;
  }

  .clip {
    min-height: 0;
    overflow: hidden;
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .reveal.open .clip {
    opacity: 1;
  }

  /* Hairline inset to line up with the title and content padding. */
  .divider {
    height: 1px;
    margin: 0 var(--spacing-n24);
    background: var(--color-input-standard-inactive);
  }

  .panel {
    padding: var(--spacing-n24);
  }
</style>
