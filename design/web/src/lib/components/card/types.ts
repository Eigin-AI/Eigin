/** Mirrors `AppCardSize`. */
export type CardSize = "large" | "small" | "compact";

/** Mirrors `AppVisualCardVariant`. */
export type VisualCardVariant = "brand" | "warm" | "soft" | "neutral";

/** Card treatment shared by every choice in an options carousel. */
export type OptionsPresentation = "compact" | "visual";

/** One card in an options carousel. Mirrors `OptionItem`; the app resolves the
    category to a symbol. */
export interface OptionChoice {
  label: string;
  description: string;
  symbol?: import("../../generated/icons").IconName;
}
