import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Eigin's markdown styling for the active theme, resolved once by `resolveTheme()`.
    @Entry var markdownRenderConfig: MarkdownRenderConfig = .default
}

extension MarkdownRenderConfig {
    /// Eigin's markdown styling for prose, headings, lists, quotes and inline runs,
    /// drawn from the design tokens. Fenced code is drawn by ``EiginCodeBlock`` and
    /// tables by ``MarkdownTableView``.
    static func eigin(colors: ResolvedColors) -> MarkdownRenderConfig {
        MarkdownRenderConfig(
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
            thematicBreakColor: colors.text.standard.muted.opacity(0.3),
            listMarkerColor: colors.text.standard.muted,
            blockQuoteBarColor: colors.border.standard.base
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
