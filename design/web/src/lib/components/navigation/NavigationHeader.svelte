<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    leading?: Snippet;
    /** Free-form center slot, grounded to the bottom like the brand avatar. */
    center?: Snippet;
    trailing?: Snippet;
    /** Renders a vertically-centered, truncating title in the center slot. */
    title?: string;
  }

  const { leading, center, trailing, title }: Props = $props();
</script>

<header class="nav-header">
  <div class="frame">
    <div class="center" class:titled={title !== undefined}>
      {#if title !== undefined}
        <span class="title t-titleXS">{title}</span>
      {:else if center}
        {@render center()}
      {/if}
    </div>

    <div class="edges">
      <div class="slot">
        {#if leading}{@render leading()}{/if}
      </div>
      <div class="slot">
        {#if trailing}{@render trailing()}{/if}
      </div>
    </div>
  </div>
</header>

<style>
  .nav-header {
    box-sizing: border-box;
    width: 100%;
    /* The header leans on the top safe-area inset, with an n4 minimum. The browser
       only reports one on an installed PWA, so the device frame supplies it. */
    padding: max(var(--spacing-n4), var(--eigin-safe-area-top, env(safe-area-inset-top)))
      var(--spacing-n16) var(--spacing-n16);
    background: var(--color-surface-standard-base);
  }

  .frame {
    position: relative;
    height: var(--spacing-n64);
  }

  /* Center sits above the edge slots, grounded to the bottom by default so a
     brand avatar lines up with the action buttons. */
  .center {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: flex-end;
    justify-content: center;
    pointer-events: none;
  }

  .center.titled {
    align-items: center;
  }

  .center > :global(*) {
    pointer-events: auto;
  }

  .title {
    /* Horizontal padding reserves room for the edge buttons so long titles
       truncate instead of sliding underneath them. The vertical padding is
       what keeps ascenders and descenders alive: the trimmed text box stops
       at cap height and baseline, so `overflow: hidden` (needed for the
       ellipsis) would otherwise slice the glyphs that spill past it. */
    padding: 0.3em var(--spacing-n64);
    color: var(--color-text-standard-base);
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .edges {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 100%;
  }

  .slot {
    display: flex;
    align-items: center;
  }
</style>
