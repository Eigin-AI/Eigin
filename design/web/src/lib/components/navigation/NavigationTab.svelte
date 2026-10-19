<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    /** 32×32 icon shown above the label. */
    icon: Snippet;
    label: string;
    selected?: boolean;
    onclick?: () => void;
  }

  const { icon, label, selected = false, onclick }: Props = $props();
</script>

<button
  class="nav-tab"
  class:selected
  type="button"
  aria-current={selected ? "page" : undefined}
  {onclick}
>
  <span class="icon">{@render icon()}</span>
  <span class="label t-navTab">{label}</span>
</button>

<style>
  .nav-tab {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    /* 8pt between icon and label, measured to the untrimmed text box.
       Trimmed text starts at cap height, so the raw gap needs the ascent
       overhang added back to match the iOS optics. */
    gap: var(--spacing-n12);
    /* Width follows the label: minimum 64px, capped at 128px. Longer
       localizations such as "Indstillinger" fit; anything wider truncates. */
    min-width: 64px;
    max-width: 128px;
    height: 64px;
    padding: 0;
    border: none;
    background: none;
    cursor: pointer;
  }

  .icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    color: var(--color-icon-standard-disabled);
    transition: color var(--motion-fast) var(--motion-easing-snap);
  }

  .nav-tab.selected .icon {
    color: var(--color-icon-standard-base);
  }

  .icon :global(svg) {
    width: 100%;
    height: 100%;
  }

  .label {
    color: var(--color-text-standard-disabled);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    /* The token's line-height (16px) is tighter than the rendered glyphs, so
       descenders would paint past the box and get clipped by overflow. The
       padding gives them room inside the box; the negative margin keeps the
       tuned icon-to-label gap unchanged. */
    padding-bottom: 0.25em;
    margin-bottom: -0.25em;
    transition: color var(--motion-fast) var(--motion-easing-snap);
  }

  .nav-tab.selected .label {
    color: var(--color-text-standard-base);
  }
</style>
