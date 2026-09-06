/** Mirrors `AppButtonVariant`. */
export type ButtonVariant = "primary" | "secondary" | "spot" | "destructive" | "open";

/** Mirrors `AppButtonSize`. */
export type ButtonSize = "large" | "medium" | "small" | "extraSmall";

/** Typography style for a button label, mirroring `AppButton.typography`. */
export function buttonTypography(size: ButtonSize): string {
  return size === "large" ? "t-buttonLarge" : size === "medium" ? "t-button" : "t-buttonSmall";
}
