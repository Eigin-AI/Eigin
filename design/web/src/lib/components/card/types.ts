/** Mirrors `AppCardSize`. */
export type CardSize = "large" | "small" | "compact";

/** Mirrors `AppVisualCardVariant`. */
export type VisualCardVariant = "brand" | "warm" | "soft" | "neutral";

/** One card in an options carousel. Mirrors `OptionItem`; the app resolves the
    category to a symbol. */
export interface OptionChoice {
  label: string;
  description: string;
  symbol?: import("../../generated/icons").IconName;
}
