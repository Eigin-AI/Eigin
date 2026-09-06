// The Eigin design system for web.
//
// One component per design-system element, grouped by family folder. The
// flat re-exports here are the library's public surface; import modules
// directly (`@lib/components/button/Button.svelte`) when you want less.

export { default as EiginRoot } from "./theme/EiginRoot.svelte";
export { default as GridScope } from "./theme/GridScope.svelte";
export { default as Icon } from "./components/icon/Icon.svelte";
export { default as Button } from "./components/button/Button.svelte";
export { default as ActionButton } from "./components/button/ActionButton.svelte";
export { default as SubtleActionButton } from "./components/button/SubtleActionButton.svelte";
export { default as CheckboxButton } from "./components/button/CheckboxButton.svelte";
export { default as SelectorButton } from "./components/button/SelectorButton.svelte";
export { default as Tag } from "./components/button/Tag.svelte";
export type { ButtonVariant, ButtonSize } from "./components/button/types";
export { default as Card } from "./components/card/Card.svelte";
export { default as CardSurface } from "./components/card/CardSurface.svelte";
export { default as OptionsCarousel } from "./components/card/OptionsCarousel.svelte";
export { default as VisualCard } from "./components/card/VisualCard.svelte";
export type { CardSize, OptionChoice, VisualCardVariant } from "./components/card/types";
export { default as Switch } from "./components/toggle/Switch.svelte";
export type { SwitchVariant } from "./components/toggle/types";
export { default as SegmentedControl } from "./components/segmented/SegmentedControl.svelte";
export type { Segment } from "./components/segmented/types";
export { default as TextInput } from "./components/input/TextInput.svelte";
export { default as ChatInput } from "./components/input/ChatInput.svelte";
export type { MicState } from "./components/input/types";
export { default as Disclosure } from "./components/disclosure/Disclosure.svelte";
export { default as OptionPicker } from "./components/disclosure/OptionPicker.svelte";
export { default as PlusMinusIndicator } from "./components/disclosure/PlusMinusIndicator.svelte";
export type { DisclosureVariant, Option } from "./components/disclosure/types";
export { default as MorphBlob } from "./components/morph/MorphBlob.svelte";
export { MorphIntensity } from "./components/morph/intensity";
export { formPath as morphFormPath } from "./components/morph/figure";
export { forms as morphForms } from "./components/morph/forms";
export { default as ThinkingIndicator } from "./components/chat/ThinkingIndicator.svelte";
export {
  stageAt as thinkingStageAt,
  thresholds as thinkingThresholds,
} from "./components/chat/thinkingCopy";
export type { ThinkingCopy } from "./components/chat/thinkingCopy";
export { default as CodeBlock } from "./components/code/CodeBlock.svelte";
export { default as MarkdownTable } from "./components/markdown/MarkdownTable.svelte";
export { default as Markdown } from "./components/markdown/Markdown.svelte";
export { default as ToolGroup } from "./components/tool/ToolGroup.svelte";
export { default as ToolRow } from "./components/tool/ToolRow.svelte";
export type { ToolCall, ToolStatus } from "./components/tool/types";
export { default as AssetRow } from "./components/asset/AssetRow.svelte";
export { timeLeftText } from "./components/asset/types";
export type { AssetState } from "./components/asset/types";
export { default as Row } from "./components/row/Row.svelte";
export { default as ContentGroup } from "./components/row/ContentGroup.svelte";
export { default as Sheet } from "./components/sheet/Sheet.svelte";
export { default as SheetHeader } from "./components/sheet/SheetHeader.svelte";
export { default as SheetActions } from "./components/sheet/SheetActions.svelte";
export type { SheetAction } from "./components/sheet/types";
export { default as ChatFeed } from "./components/chat/ChatFeed.svelte";
export { default as OptionsGroup } from "./components/chat/OptionsGroup.svelte";
export { default as ChatBrandMessage } from "./components/chat/ChatBrandMessage.svelte";
export { default as ChatUserMessage } from "./components/chat/ChatUserMessage.svelte";
export { default as CompactionDivider } from "./components/chat/CompactionDivider.svelte";
export { StreamThrottler, wholeWords } from "./components/chat/streamThrottler";
export type { StreamPhase, StreamThrottlerOptions } from "./components/chat/streamThrottler";
export { ChasingProgress } from "./components/chat/chasingProgress";
export { driveFrames } from "./internal/driveFrames";
export { default as BrandAvatar } from "./components/navigation/BrandAvatar.svelte";
export { default as NavigationBar } from "./components/navigation/NavigationBar.svelte";
export { default as NavigationHeader } from "./components/navigation/NavigationHeader.svelte";
export { default as NavigationTab } from "./components/navigation/NavigationTab.svelte";
export type { NavigationBarBackground } from "./components/navigation/types";

export type {
  TypographyName,
  TypographyStyle,
  GridBreakpointName,
  ColorToken,
  ScaleToken,
  ScaleGroup,
  EasingToken,
} from "./generated/tokens";
export {
  typographyNames,
  typographyStyles,
  colorTokens,
  scaleGroups,
  motionEasings,
} from "./generated/tokens";
export type { IconName } from "./generated/icons";
export { icons } from "./generated/icons";
