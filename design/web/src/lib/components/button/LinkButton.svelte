<script lang="ts">
  import type { HTMLAnchorAttributes } from "svelte/elements";
  import { buttonTypography, type ButtonSize, type ButtonVariant } from "./types";
  import "./button.css";

  let {
    href,
    label,
    onclick,
    variant = "primary",
    size = "medium",
  }: {
    /** Navigation destination. Use Button for actions without a destination. */
    href: string;
    label: string;
    onclick?: HTMLAnchorAttributes["onclick"];
    variant?: ButtonVariant;
    size?: ButtonSize;
  } = $props();
</script>

<a class="eigin-btn {variant} {size}" {href} {onclick}>
  <span class={buttonTypography(size)}>{label}</span>
</a>

<style>
  a {
    text-decoration: none;
  }
</style>
