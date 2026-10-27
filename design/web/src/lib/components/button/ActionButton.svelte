<script lang="ts">
  import Icon from "../icon/Icon.svelte";
  import type { IconName } from "../../generated/icons";
  import type { ButtonSize, ButtonVariant } from "./types";
  import "./button.css";

  let {
    icon,
    variant = "primary",
    size = "large",
    disabled = false,
    label,
    onclick,
  }: {
    icon: IconName;
    /** Accessible name — icon-only buttons have no visible text. */
    label?: string;
    variant?: ButtonVariant;
    size?: ButtonSize;
    disabled?: boolean;
    onclick?: (event: MouseEvent) => void;
  } = $props();

  /* px mirrors of `Sizing.Button.Icon` (tokens: --sizing-button-icon-*). */
  const iconPxBySize: Record<ButtonSize, number> = {
    large: 40,
    medium: 24,
    small: 24,
    extraSmall: 24,
  };

  /* Mirrors `AppActionButton.iconColor` — text/button on filled variants,
     icon/standard on transparent ones. */
  function iconColor(variant: ButtonVariant, disabled: boolean): string {
    if (disabled) {
      return variant === "spot" || variant === "destructive"
        ? "var(--color-icon-impact-disabled)"
        : "var(--color-icon-standard-disabled)";
    }
    switch (variant) {
      case "primary":
        return "var(--color-text-button-onPrimary)";
      case "outline":
      case "elevated":
        return "var(--color-text-standard-base)";
      case "secondary":
        return "var(--color-icon-standard-base)";
      case "spot":
        return "var(--color-icon-impact-base)";
      case "destructive":
        return "var(--color-icon-impact-base)";
      case "open":
        return "var(--color-icon-standard-base)";
    }
  }
</script>

<button class="eigin-btn action {variant} {size}" aria-label={label} {disabled} {onclick}>
  <span class="glyph" style:color={iconColor(variant, disabled)}>
    <Icon name={icon} size={iconPxBySize[size]} />
  </span>
</button>
