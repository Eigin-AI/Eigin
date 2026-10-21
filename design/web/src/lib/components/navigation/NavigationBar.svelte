<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    /** NavigationTab items, spread across the bar. */
    children: Snippet;
  }

  const { children }: Props = $props();
</script>

<!-- Has no surface of its own: it floats over the screen, content softens beneath. -->
<nav class="nav-bar">
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
</style>
