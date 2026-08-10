import SwiftStreamingMarkdown
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Eigin's markdown styling for the active theme, resolved once by `resolveTheme()`.
    @Entry var markdownRenderConfig: MarkdownRenderConfig = .default
}

extension MarkdownRenderConfig {
    /// Eigin's markdown styling for prose, headings, lists, quotes, inline runs and
    /// tables, drawn from the design tokens. Fenced code is drawn by ``EiginCodeBlock``.
    ///
    /// - Parameter animatesText: fades newly appended words in. Off by default; the
    ///   ``StreamThrottler`` already paces the reveal.
    static func eigin(colors: ResolvedColors, animatesText: Bool = false) -> MarkdownRenderConfig {
        MarkdownRenderConfig(
            shouldAnimateText: animatesText,
            blockQuoteStyle: MarkdownTextStyle(
                textFonts: Typography.chatMessage.textFonts,
                textColor: colors.text.standard.muted
            ),
            headingStyle: MarkdownHeadingTextStyle(
                h1Font: Typography.titleXl.textFonts,
                h2Font: Typography.titleL.textFonts,
                h3Font: Typography.titleM.textFonts,
                h4Font: Typography.titleS.textFonts,
                h5Font: Typography.titleS.textFonts,
                h6Font: Typography.titleS.textFonts,
                textColor: colors.text.standard.base
            ),
            orderedListStyle: MarkdownTextStyle(
                textFonts: Typography.chatMessage.textFonts,
                textColor: colors.text.standard.base
            ),
            paragraphStyle: MarkdownTextStyle(
                textFonts: Typography.chatMessage.textFonts,
                textColor: colors.text.standard.base
            ),
            tableStyle: MarkdownTableTextStyle(
                textFonts: Typography.body.textFonts,
                headerTextColor: colors.text.standard.base,
                regularTextColor: colors.text.standard.base,
                headerBackgroundColor: colors.surface.standard.elevated,
                borderColor: colors.border.standard.base,
                actionButtonColor: colors.accent
            ),
            inlineStyle: MarkdownInlineTextStyle(
                boldTextColor: colors.text.standard.base,
                linkTextFont: Typography.chatMessage.uiFont,
                linkTextColor: colors.accent,
                codeTextFont: Typography.code.uiFont,
                codeTextColor: colors.text.standard.muted,
                codeBackgroundColor: colors.surface.standard.elevated,
                codeUnderlineColor: .clear
            ),
            blockSpacing: Spacing.n16,
            // Drops the library's "Select more text" item.
            textSelectionConfig: TextSelectionConfig(isEnabled: false),
            thematicBreakColor: colors.text.standard.muted.opacity(0.3)
        )
    }
}

private extension TypographyStyle {
    /// The token's face with its bold and italic siblings, resolved by PostScript name.
    /// Missing siblings fall back to `normal`.
    var textFonts: TextFonts {
        TextFonts(
            normal: uiFont,
            italic: sibling("Italic"),
            bold: sibling("Bold"),
            boldItalic: sibling("BoldItalic"),
            preferredLetterSpacing: tracking == 0 ? nil : tracking,
            preferredLineHeight: lineSpacing.map { uiFont.lineHeight + $0 }
        )
    }

    func sibling(_ face: String) -> UIFont? {
        guard let family = uiFont.fontName.split(separator: "-").first else { return nil }
        return UIFont(name: "\(family)-\(face)", size: uiFont.pointSize)
    }
}
