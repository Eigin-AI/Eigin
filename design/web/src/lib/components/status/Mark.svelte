<script lang="ts">
  import Icon from "../icon/Icon.svelte";
  import type { IconName } from "../../generated/icons";

  const {
    icon,
    emoji,
    letter,
    size = 64,
  }: { icon?: IconName; emoji?: string; letter?: string; size?: number } = $props();
</script>

<!--
  A connection's mark: its logo where we have one, its initial where we don't.

  Most of what people connect has no asset we can ship — an IMAP account, a
  server someone runs, an agent at a URL. A letter in the same circle keeps
  those from looking broken beside the ones that do, and it means a screen's
  layout never depends on whether an asset exists.
-->
<span class="mark" style:width="{size}px" style:height="{size}px">
  {#if icon}
    <Icon name={icon} size={Math.round(size / 2)} />
  {:else if emoji}
    <span class="emoji" style:font-size="{Math.round(size / 2.1)}px">{emoji}</span>
  {:else if letter}
    <span class="letter" style:font-size="{Math.round(size / 2)}px">{letter}</span>
  {/if}
</span>

<style>
  .mark {
    display: inline-flex;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: var(--radius-full);
    background: var(--color-surface-standard-elevated);
    color: var(--color-text-standard-base);
  }

  .emoji {
    line-height: 1;
  }

  /* The letter stands in for a logo, so it carries the same weight a logo
     would: muted, it read as a disabled row beside the marks it sits with. */
  .letter {
    font-family: var(--font-display);
    font-weight: 700;
    line-height: 1;
    color: var(--color-text-standard-base);
  }
</style>
