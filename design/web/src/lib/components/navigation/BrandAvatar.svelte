<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    /** Rendered inside the circle, inset so it never touches the edge. */
    children: Snippet;
    /** The agent's symbol, shown on a neutral vessel; overrides children. */
    emoji?: string;
    /** Diameter in px. */
    size?: number;
    /** Inset between the circle edge and the content. */
    inset?: number;
    /** Renders as a button when provided. */
    onclick?: () => void;
    label?: string;
  }

  const { children, emoji, size = 56, inset = 8, onclick, label }: Props = $props();
</script>

{#if onclick}
  <button
    class="brand-avatar"
    class:has-emoji={emoji}
    type="button"
    aria-label={label}
    style:--avatar-size="{size}px"
    style:--avatar-inset="{inset}px"
    {onclick}
  >
    {#if emoji}
      <span class="emoji" style:font-size="{Math.round(size * 0.55)}px">{emoji}</span>
    {:else}
      {@render children()}
    {/if}
  </button>
{:else}
  <div
    class="brand-avatar"
    class:has-emoji={emoji}
    style:--avatar-size="{size}px"
    style:--avatar-inset="{inset}px"
  >
    {#if emoji}
      <span class="emoji" style:font-size="{Math.round(size * 0.55)}px">{emoji}</span>
    {:else}
      {@render children()}
    {/if}
  </div>
{/if}

<style>
  .brand-avatar {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    box-sizing: border-box;
    width: var(--avatar-size);
    height: var(--avatar-size);
    padding: var(--avatar-inset);
    border: none;
    border-radius: var(--radius-full);
    background: var(--color-surface-impact-base);
    color: var(--color-text-standard-base);
  }

  /* Once the agent has a face, the circle softens to a neutral surface —
     the same swap the onboarding avatar makes. */
  .brand-avatar.has-emoji {
    background: var(--color-surface-standard-elevated);
  }

  button.brand-avatar {
    cursor: pointer;
    transition: opacity var(--motion-fast) var(--motion-easing-snap);
  }

  button.brand-avatar:active {
    opacity: 0.7;
  }

  .brand-avatar :global(svg) {
    width: 100%;
    height: 100%;
  }

  .emoji {
    line-height: 1;
  }
</style>
