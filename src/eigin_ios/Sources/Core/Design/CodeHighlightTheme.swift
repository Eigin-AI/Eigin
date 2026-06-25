import SwiftUI
import Textual

extension StructuredText.HighlighterTheme {
    /// Syntax-highlighting theme built from the active color scheme's `code` tokens, so token
    /// colors stay in step with the palette and adapt to light/dark and theme changes.
    ///
    /// The background color is unused by ``EiginCodeBlockStyle`` (it paints its own surface), but
    /// is kept consistent so the theme reads well anywhere Textual applies it directly.
    static func eigin(_ colors: ResolvedColors) -> Self {
        let code = colors.code
        return Self(
            foregroundColor: DynamicColor(code.plain),
            backgroundColor: DynamicColor(colors.surface.standard.elevated),
            tokenProperties: [
                // Keywords and language literals.
                .keyword: AnyTextProperty(.foregroundColor(code.keyword), .fontWeight(.semibold)),
                .literal: AnyTextProperty(.foregroundColor(code.keyword), .fontWeight(.semibold)),
                .boolean: AnyTextProperty(.foregroundColor(code.keyword), .fontWeight(.semibold)),
                // Types, classes, builtins, and markup.
                .builtin: AnyTextProperty(.foregroundColor(code.type)),
                .className: AnyTextProperty(.foregroundColor(code.type)),
                .tag: AnyTextProperty(.foregroundColor(code.type)),
                .attribute: AnyTextProperty(.foregroundColor(code.type)),
                .attributeName: AnyTextProperty(.foregroundColor(code.type)),
                .preprocessor: AnyTextProperty(.foregroundColor(code.type)),
                .directive: AnyTextProperty(.foregroundColor(code.type)),
                // Functions.
                .function: AnyTextProperty(.foregroundColor(code.function)),
                .functionName: AnyTextProperty(.foregroundColor(code.function)),
                // Strings and characters.
                .string: AnyTextProperty(.foregroundColor(code.string)),
                .char: AnyTextProperty(.foregroundColor(code.string)),
                .regex: AnyTextProperty(.foregroundColor(code.string)),
                // Numbers and constants.
                .number: AnyTextProperty(.foregroundColor(code.number)),
                .constant: AnyTextProperty(.foregroundColor(code.number)),
                // Variables and properties.
                .variable: AnyTextProperty(.foregroundColor(code.variable)),
                .property: AnyTextProperty(.foregroundColor(code.variable)),
                // Comments.
                .comment: AnyTextProperty(.foregroundColor(code.comment)),
                .blockComment: AnyTextProperty(.foregroundColor(code.comment)),
                .docComment: AnyTextProperty(.foregroundColor(code.comment)),
                .mark: AnyTextProperty(.foregroundColor(code.comment), .fontWeight(.bold)),
                // Links and diff markers.
                .url: AnyTextProperty(.foregroundColor(code.link)),
                .inserted: AnyTextProperty(.foregroundColor(code.inserted)),
                .deleted: AnyTextProperty(.foregroundColor(code.deleted)),
            ]
        )
    }
}
