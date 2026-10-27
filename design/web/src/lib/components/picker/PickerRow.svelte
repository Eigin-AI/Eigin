<script lang="ts">
  import type { Snippet } from "svelte";
  import Icon from "../icon/Icon.svelte";

  let {
    selected,
    href,
    lang,
    hreflang,
    onclick,
    children,
  }: {
    /** Omit for an action row without a selection indicator. */
    selected?: boolean;
    /** A destination makes this row a link; otherwise it is a button. */
    href?: string;
    lang?: string;
    hreflang?: string;
    onclick?: () => void;
    /** Row content, such as a label, icon, or description. */
    children: Snippet;
  } = $props();
</script>

{#snippet content()}
  <span class="row-content">{@render children()}</span>
  {#if selected !== undefined}
    <span class="check" class:visible={selected} aria-hidden="true"
      ><Icon name="functional/check" size={16} /></span
    >
  {/if}
{/snippet}

{#if href}
  <a
    class="picker-row"
    class:selected
    {href}
    {lang}
    {hreflang}
    {onclick}
    aria-current={selected ? "page" : undefined}>{@render content()}</a
  >
{:else}
  <button type="button" class="picker-row" class:selected {onclick} aria-pressed={selected}
    >{@render content()}</button
  >
{/if}

<style>
  .picker-row {
    display: flex;
    align-items: center;
    gap: var(--spacing-n24);
    width: 100%;
    min-height: 20px;
    padding: 0;
    border: none;
    background: transparent;
    font-family: inherit;
    text-align: left;
    text-decoration: none;
    color: var(--color-text-standard-muted);
    cursor: pointer;
  }
  .picker-row.selected,
  .picker-row:hover {
    color: var(--color-text-standard-base);
  }
  .row-content {
    flex: 1;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .check {
    display: inline-flex;
    color: var(--color-icon-standard-base);
    visibility: hidden;
  }
  .check.visible {
    visibility: visible;
  }
  .picker-row:focus-visible {
    outline: 2px solid var(--color-interaction-border-focus);
    outline-offset: 4px;
  }
</style>
