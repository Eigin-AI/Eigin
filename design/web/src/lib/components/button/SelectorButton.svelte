<script lang="ts">
  import Button from "./Button.svelte";
  import Icon from "../icon/Icon.svelte";
  import type { ButtonSize, ButtonVariant } from "./types";

  let {
    label,
    isSelected = false,
    variant = "secondary",
    size = "large",
    disabled = false,
    onclick,
  }: {
    label: string;
    isSelected: boolean;
    variant?: ButtonVariant;
    size?: ButtonSize;
    disabled?: boolean;
    onclick?: (event: MouseEvent) => void;
  } = $props();
</script>

<Button {label} {variant} {size} {disabled} {onclick}>
  {#snippet trailing()}
    {#if isSelected}
      <span class="glyph"><Icon name="functional/check" size={20} /></span>
    {:else}
      <span class="glyph muted"><Icon name="functional/circle" size={20} /></span>
    {/if}
  {/snippet}
</Button>

<style>
  /* The selection marker: check when chosen, circle when not. */
  .glyph {
    display: inline-flex;
    color: var(--color-icon-standard-base);
    transition: color var(--motion-normal) var(--motion-easing-smooth);
  }

  .glyph.muted {
    color: var(--color-icon-standard-muted);
  }
</style>
