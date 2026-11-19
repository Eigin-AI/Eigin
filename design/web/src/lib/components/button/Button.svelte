<script lang="ts">
  import type { Snippet } from "svelte";
  import { buttonTypography, type ButtonSize, type ButtonVariant } from "./types";
  import "./button.css";

  let {
    label,
    variant = "primary",
    size = "large",
    disabled = false,
    type,
    onclick,
    trailing,
  }: {
    label: string;
    /** Mirrors `AppButtonVariant`. */
    variant?: ButtonVariant;
    /** Mirrors `AppButtonSize`. */
    size?: ButtonSize;
    disabled?: boolean;
    /** Native form action: submit sends the form, reset restores its values, button only runs its click handler. Omitted uses the browser default. */
    type?: "button" | "submit" | "reset";
    onclick?: (event: MouseEvent) => void;
    /** Optional element pinned to the far edge, like `AppButton.trailing`. */
    trailing?: Snippet;
  } = $props();
</script>

<button
  class="eigin-btn {variant} {size}"
  class:has-trailing={trailing}
  {disabled}
  {type}
  {onclick}
>
  <span class={buttonTypography(size)}>{label}</span>
  {#if trailing}
    <span class="eigin-trailing-spacer"></span>
    {@render trailing()}
  {/if}
</button>
