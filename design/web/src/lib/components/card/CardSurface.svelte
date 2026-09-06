<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    padding = 24,
    action,
    children,
  }: {
    /** Interior padding in px; defaults to `Spacing.n24`. */
    padding?: number;
    /** Pass to make the whole card tappable. */
    action?: () => void;
    children: Snippet;
  } = $props();
</script>

<!--
  A generic rounded, elevated card shell for
  arbitrary content. Fills the available width.
-->
{#if action}
  <button class="surface tappable" style:padding="{padding}px" onclick={action} type="button">
    {@render children()}
  </button>
{:else}
  <div class="surface" style:padding="{padding}px">
    {@render children()}
  </div>
{/if}

<style>
  .surface {
    position: relative;
    box-sizing: border-box;
    display: block;
    width: 100%;
    background: var(--color-surface-standard-alternative);
    border-radius: var(--radius-card);
    border: none;
    text-align: left;
    font-family: inherit;
    color: inherit;
  }

  .surface.tappable {
    cursor: pointer;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .surface.tappable::after {
    content: "";
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background: var(--color-interaction-light-hover);
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
    pointer-events: none;
  }

  .surface.tappable:hover::after {
    opacity: 1;
  }

  /* A tap fades the card toward the surface behind rather than washing it:
     a dark wash both darkened and cooled a warm card. */
  .surface.tappable:active {
    opacity: 0.75;
    transition: opacity var(--motion-fast) var(--motion-easing-snap);
  }
</style>
