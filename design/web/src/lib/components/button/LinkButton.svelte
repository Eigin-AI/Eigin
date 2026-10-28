<script lang="ts">
  import type { HTMLAnchorAttributes } from "svelte/elements";
  import Icon from "../icon/Icon.svelte";
  import type { IconName } from "../../generated/icons";
  import { buttonTypography, type ButtonSize, type ButtonVariant } from "./types";
  import "./button.css";

  let {
    href,
    label,
    icon,
    onclick,
    variant = "primary",
    size = "medium",
  }: {
    /** Navigation destination. Use Button for actions without a destination. */
    href: string;
    label: string;
    /** Render an icon-only navigation button; label remains its accessible name. */
    icon?: IconName;
    onclick?: HTMLAnchorAttributes["onclick"];
    variant?: ButtonVariant;
    size?: ButtonSize;
  } = $props();
</script>

<a
  class="eigin-btn {variant} {size}"
  class:action={!!icon}
  aria-label={icon ? label : undefined}
  title={icon ? label : undefined}
  {href}
  {onclick}
>
  {#if icon}
    <Icon name={icon} size={size === "large" ? 40 : 24} />
  {:else}
    <span class={buttonTypography(size)}>{label}</span>
  {/if}
</a>

<style>
  a {
    text-decoration: none;
  }
</style>
