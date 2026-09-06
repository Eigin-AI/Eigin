/** Mirrors `AppDisclosureVariant`. */
export type DisclosureVariant = "card" | "open";

/** One selectable row in an `OptionPicker`. Mirrors `AppOption`. */
export interface Option<Value extends string = string> {
  value: Value;
  label: string;
  /** Optional trailing detail, e.g. a dialect or region. */
  detail?: string;
}
