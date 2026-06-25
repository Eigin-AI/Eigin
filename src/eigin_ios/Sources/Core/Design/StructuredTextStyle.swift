import SwiftUI
import Textual

extension InlineStyle {
    static func eigin(colors: ResolvedColors) -> InlineStyle {
        InlineStyle()
            .strong(.bold)
            .code(
                .font(Typography.code.font),
                .foregroundColor(colors.text.standard.muted)
            )
            .link(.foregroundColor(Color.accentColor))
    }
}

extension View {
    /// Applies Eigin's shared `StructuredText` styling: inline style, headings, the rounded
    /// ``EiginCodeBlockStyle`` code card, and the ``StructuredText/HighlighterTheme/eigin``
    /// syntax theme.
    ///
    /// - Parameter highlightSyntax: When false, uses the `.plain` highlighter theme, which skips
    ///   the syntax tokenizer entirely. Set false while a code block is still streaming so we don't
    ///   re-tokenize on every chunk.
    func eiginStructuredText(colors: ResolvedColors, highlightSyntax: Bool = true) -> some View {
        textual.inlineStyle(.eigin(colors: colors))
            .textual.headingStyle(EiginHeadingStyle())
            .textual.codeBlockStyle(EiginCodeBlockStyle())
            .textual.highlighterTheme(highlightSyntax ? .eigin(colors) : .plain)
    }
}

struct EiginHeadingStyle: StructuredText.HeadingStyle {
    func makeBody(configuration: Configuration) -> some View {
        let level = min(configuration.headingLevel, 6)
        let font: Font = switch level {
        case 1: Typography.titleXl.font
        case 2: Typography.titleL.font
        case 3: Typography.titleM.font
        default: Typography.titleS.font
        }
        let textCase: Text.Case? = switch level {
        case 1, 2: .uppercase
        default: nil
        }
        configuration.label
            .font(font)
            .textCase(textCase)
            .textual.blockSpacing(.fontScaled(top: 1.6, bottom: 0.8))
    }
}
