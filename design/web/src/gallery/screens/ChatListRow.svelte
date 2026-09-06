<script lang="ts">
  import { Icon } from "@lib";

  let {
    title,
    preview,
    emoji,
  }: {
    title: string;
    preview: string;
    /** The chat's space, when it has one; otherwise a bubble stands in. */
    emoji?: string;
  } = $props();
</script>

<!-- A chat in the list: space avatar, title, and the last thing said. -->
<button class="chat-row" type="button">
  <span class="avatar">
    {#if emoji}
      <span class="t-note">{emoji}</span>
    {:else}
      <span class="fallback"><Icon name="functional/note" size={16} /></span>
    {/if}
  </span>

  <span class="text">
    <span class="t-titleXS title">{title}</span>
    <span class="t-body preview">{preview}</span>
  </span>
</button>

<style>
  .chat-row {
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
    width: 100%;
    box-sizing: border-box;
    padding: var(--spacing-n8) 0;
    background: none;
    border: none;
    font-family: inherit;
    text-align: left;
    cursor: pointer;
  }

  /* 36pt; hard-coded — no sizing token covers it. */
  .avatar {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex: none;
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    background: var(--color-surface-standard-alternative);
  }

  .fallback {
    display: inline-flex;
    color: var(--color-accent);
  }

  .text {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n4);
    min-width: 0;
  }

  .title {
    color: var(--color-text-standard-base);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    /* Trimmed text must not be clipped by the ellipsis box. */
    text-box: normal;
  }

  /* Two lines, always: the space is reserved so rows keep one height. */
  .preview {
    color: var(--color-text-standard-muted);
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    overflow: hidden;
    min-height: calc(2lh);
    text-box: normal;
  }
</style>
