<script lang="ts">
  import type { Snippet } from "svelte";
  import type { NavigationBarBackground } from "./types";

  interface Props {
    /** NavigationTab items, spread across the bar. */
    children: Snippet;
    background?: NavigationBarBackground;
  }

  const { children, background = "surface" }: Props = $props();
</script>

<nav class="nav-bar {background}">
  {@render children()}
</nav>

<style>
  .nav-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    box-sizing: border-box;
    padding: var(--spacing-n8) var(--spacing-n48) var(--spacing-n24);
  }

  .nav-bar.surface {
    background: var(--color-surface-standard-base);
    border-radius: var(--radius-card) var(--radius-card) 0 0;
  }

  .nav-bar.clear {
    background: none;
  }
</style>
