import { typographyStyles } from "@eigin/ui";

/** Make generated typography metrics available to Markdown and native form CSS. */
export const typeProperties = typographyStyles
  .map(
    (style) =>
      `--portal-${style.name}-size:${style.fontSize}px;--portal-${style.name}-leading:${style.lineHeight}px;--portal-${style.name}-leading-ratio:${style.lineHeight / style.fontSize};--portal-${style.name}-weight:${style.fontWeight}`,
  )
  .join(";");
