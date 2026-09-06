import type { IconName } from "../../generated/icons";

/** One action in a `SheetActions` list. */
export interface SheetAction {
  label: string;
  icon: IconName;
  disabled?: boolean;
  onclick?: () => void;
}
