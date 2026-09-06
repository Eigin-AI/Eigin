<script lang="ts">
  import type { Snippet } from "svelte";
  import Button from "./Button.svelte";
  import type { ButtonSize } from "./types";

  let {
    label,
    icon,
    size = "large",
    disabled = false,
    onclick,
  }: {
    label: string;
    icon: Snippet;
    /** Mirrors `AppSubtleActionButton`. */
    size?: ButtonSize;
    disabled?: boolean;
    onclick?: (event: MouseEvent) => void;
  } = $props();
</script>

<Button {label} variant="secondary" {size} {disabled} {onclick}>
  {#snippet trailing()}
    <span class="glyph">{@render icon()}</span>
  {/snippet}
</Button>

<style>
  /* Mirrors `AppSubtleActionButton`: trailing icon uses icon.standard.base,
     not the button's onSecondary text color. */
  .glyph {
    display: inline-flex;
    color: var(--color-icon-standard-base);
  }
</style>
