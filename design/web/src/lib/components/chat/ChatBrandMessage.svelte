<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    /** Rendered directly in the container — brand messages have no bubble. */
    children: Snippet;
  }

  const { children }: Props = $props();
</script>

<div class="brand-message">
  {@render children()}
</div>

<style>
  .brand-message {
    box-sizing: border-box;
    width: 100%;
    padding: 0 var(--chat-px-large);
  }
</style>
