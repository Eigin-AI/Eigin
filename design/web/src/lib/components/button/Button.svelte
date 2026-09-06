<script lang="ts">
  import type { Snippet } from "svelte";
  import { buttonTypography, type ButtonSize, type ButtonVariant } from "./types";
  import "./button.css";

  let {
    label,
    variant = "primary",
    size = "large",
    disabled = false,
    onclick,
    trailing,
  }: {
    label: string;
    /** Mirrors `AppButtonVariant`. */
    variant?: ButtonVariant;
    /** Mirrors `AppButtonSize`. */
    size?: ButtonSize;
    disabled?: boolean;
    onclick?: (event: MouseEvent) => void;
    /** Optional element pinned to the far edge, like `AppButton.trailing`. */
    trailing?: Snippet;
  } = $props();
</script>

<button class="eigin-btn {variant} {size}" class:has-trailing={trailing} {disabled} {onclick}>
  <span class={buttonTypography(size)}>{label}</span>
  {#if trailing}
    <span class="eigin-trailing-spacer"></span>
    {@render trailing()}
  {/if}
</button>
