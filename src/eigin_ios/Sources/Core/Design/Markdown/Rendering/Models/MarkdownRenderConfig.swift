import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Styling applied to the markdown renderer: fonts and colors for the block and
/// inline runs Eigin renders through this pipeline. Built from design tokens by
/// `MarkdownRenderConfig.eigin(colors:)`.
struct MarkdownRenderConfig: Hashable, Sendable {
    /// Styling applied to block-quote content.
    let blockQuoteStyle: MarkdownTextStyle
    /// Per-level heading styling.
    let headingStyle: MarkdownHeadingTextStyle
    /// Styling applied to ordered list items.
    let orderedListStyle: MarkdownTextStyle
    /// Styling applied to paragraph text.
    let paragraphStyle: MarkdownTextStyle
    /// Styling applied to inline runs such as bold, links, and inline code.
    let inlineStyle: MarkdownInlineTextStyle
    /// Vertical spacing between adjacent blocks.
    let blockSpacing: CGFloat
    /// Color of the horizontal rule rendered for a thematic break (`---`).
    let thematicBreakColor: Color
    /// Color of list markers: bullets, ordered numbers, and task checkboxes.
    let listMarkerColor: Color
    /// Color of the vertical bar drawn beside block quotes.
    let blockQuoteBarColor: Color

    /// Font and color style for a uniformly-styled run of markdown text.
    struct MarkdownTextStyle: Hashable, Sendable {
        /// Font set used for normal, bold, and italic variants.
        let textFonts: TextFonts
        /// Foreground color applied to the text.
        let textColor: Color

        /// Create a text style with the given fonts and foreground color.
        init(textFonts: TextFonts, textColor: Color) {
            self.textFonts = textFonts
            self.textColor = textColor
        }

        /// Attributes for a plain run of this style. Carries `.typography` so the
        /// renderer can read the line box back from the attributed string.
        var plainTextAttributes: [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: textFonts.normal,
                .foregroundColor: MDColor(textColor),
                .typography: textFonts,
            ]
            if let kern = textFonts.preferredLetterSpacing {
                attributes[.kern] = kern
            }
            return attributes
        }
    }

    /// Per-level fonts and shared foreground color for markdown headings.
    struct MarkdownHeadingTextStyle: Hashable, Sendable {
        let h1Font: TextFonts
        let h2Font: TextFonts
        let h3Font: TextFonts
        let h4Font: TextFonts
        let h5Font: TextFonts
        let h6Font: TextFonts
        /// Foreground color shared by every heading level.
        let textColor: Color

        /// Create a heading style with explicit fonts per level and a shared color.
        init(
            h1Font: TextFonts,
            h2Font: TextFonts,
            h3Font: TextFonts,
            h4Font: TextFonts,
            h5Font: TextFonts,
            h6Font: TextFonts,
            textColor: Color
        ) {
            self.h1Font = h1Font
            self.h2Font = h2Font
            self.h3Font = h3Font
            self.h4Font = h4Font
            self.h5Font = h5Font
            self.h6Font = h6Font
            self.textColor = textColor
        }
    }

    /// Styling for inline runs: bold emphasis, links, and inline code spans.
    struct MarkdownInlineTextStyle: Hashable, Sendable {
        /// Foreground color applied to bold-emphasis runs.
        let boldTextColor: Color
        /// Font used for link runs.
        let linkTextFont: MDFont
        /// Foreground color applied to link runs.
        let linkTextColor: Color
        /// Underline style applied to link runs.
        let linkUnderlineStyle: NSUnderlineStyle
        /// Font used for inline code spans.
        let codeTextFont: MDFont
        /// Foreground color applied to inline code spans.
        let codeTextColor: Color
        /// Background fill behind inline code spans.
        let codeBackgroundColor: Color
        /// Underline color drawn beneath inline code spans.
        let codeUnderlineColor: Color

        /// Create an inline text style with the supplied fonts and color palette.
        init(
            boldTextColor: Color,
            linkTextFont: MDFont,
            linkTextColor: Color,
            codeTextFont: MDFont,
            codeTextColor: Color,
            codeBackgroundColor: Color,
            codeUnderlineColor: Color
        ) {
            self.init(
                boldTextColor: boldTextColor,
                linkTextFont: linkTextFont,
                linkTextColor: linkTextColor,
                linkUnderlineStyle: [],
                codeTextFont: codeTextFont,
                codeTextColor: codeTextColor,
                codeBackgroundColor: codeBackgroundColor,
                codeUnderlineColor: codeUnderlineColor
            )
        }

        /// Create an inline text style with the supplied fonts, color palette, and link underline
        /// style.
        init(
            boldTextColor: Color,
            linkTextFont: MDFont,
            linkTextColor: Color,
            linkUnderlineStyle: NSUnderlineStyle,
            codeTextFont: MDFont,
            codeTextColor: Color,
            codeBackgroundColor: Color,
            codeUnderlineColor: Color
        ) {
            self.boldTextColor = boldTextColor
            self.linkTextFont = linkTextFont
            self.linkTextColor = linkTextColor
            self.linkUnderlineStyle = linkUnderlineStyle
            self.codeTextFont = codeTextFont
            self.codeTextColor = codeTextColor
            self.codeBackgroundColor = codeBackgroundColor
            self.codeUnderlineColor = codeUnderlineColor
        }
    }

    /// Create a render config.
    init(
        blockQuoteStyle: MarkdownTextStyle,
        headingStyle: MarkdownHeadingTextStyle,
        orderedListStyle: MarkdownTextStyle,
        paragraphStyle: MarkdownTextStyle,
        inlineStyle: MarkdownInlineTextStyle,
        blockSpacing: CGFloat,
        thematicBreakColor: Color,
        listMarkerColor: Color,
        blockQuoteBarColor: Color
    ) {
        self.blockQuoteStyle = blockQuoteStyle
        self.headingStyle = headingStyle
        self.orderedListStyle = orderedListStyle
        self.paragraphStyle = paragraphStyle
        self.inlineStyle = inlineStyle
        self.blockSpacing = blockSpacing
        self.thematicBreakColor = thematicBreakColor
        self.listMarkerColor = listMarkerColor
        self.blockQuoteBarColor = blockQuoteBarColor
    }

    /// A neutral fallback used only as the environment default; the app always
    /// injects `MarkdownRenderConfig.eigin(colors:)`.
    static let `default`: MarkdownRenderConfig = {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let fonts = TextFonts(
            normal: body,
            italic: nil,
            bold: nil,
            boldItalic: nil,
            preferredLetterSpacing: nil,
            preferredLineHeight: nil
        )
        let code = UIFont.monospacedSystemFont(ofSize: body.pointSize, weight: .regular)
        return MarkdownRenderConfig(
            blockQuoteStyle: MarkdownTextStyle(textFonts: fonts, textColor: .secondary),
            headingStyle: MarkdownHeadingTextStyle(
                h1Font: fonts,
                h2Font: fonts,
                h3Font: fonts,
                h4Font: fonts,
                h5Font: fonts,
                h6Font: fonts,
                textColor: .primary
            ),
            orderedListStyle: MarkdownTextStyle(textFonts: fonts, textColor: .primary),
            paragraphStyle: MarkdownTextStyle(textFonts: fonts, textColor: .primary),
            inlineStyle: MarkdownInlineTextStyle(
                boldTextColor: .primary,
                linkTextFont: body,
                linkTextColor: .accentColor,
                codeTextFont: code,
                codeTextColor: .primary,
                codeBackgroundColor: Color(.secondarySystemBackground),
                codeUnderlineColor: .clear
            ),
            blockSpacing: 16,
            thematicBreakColor: .secondary,
            listMarkerColor: .secondary,
            blockQuoteBarColor: .secondary
        )
    }()
}
