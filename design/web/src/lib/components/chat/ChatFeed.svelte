<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    /** Chat messages, stacked at the token message gap. */
    children: Snippet;
  }

  const { children }: Props = $props();
</script>

<div class="feed">
  {@render children()}
</div>

<style>
  /* Messages are spaced by Sizing.Chat.Gap.message; the horizontal insets
     belong to the messages themselves, since user and brand differ. */
  .feed {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-chat-gap-message);
    width: 100%;
  }
</style>
