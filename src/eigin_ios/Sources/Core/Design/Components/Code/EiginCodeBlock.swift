import HighlightSwift
import SwiftUI

/// A rounded Eigin code card: token-styled surface, Fira Code, and horizontal scrolling
/// for long lines.
///
/// Shared by chat code blocks, the error detail sheet and the tool detail sheet, so every
/// code surface in the app looks the same.
struct EiginCodeBlock: View {
    let code: String
    var language: String?
    /// When false the code renders unhighlighted. Set false while streaming: highlighting
    /// round-trips through an HTML parse, too expensive to repeat per chunk.
    var highlightSyntax: Bool = true

    @Environment(\.colors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @State private var highlighted: AttributedString?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            codeText
                .font(Typography.code.font)
                .lineSpacing(Typography.code.lineSpacing ?? 0)
                .foregroundStyle(colors.code.plain)
                // Horizontal gains the font's line-box inset so the padding reads as even.
                .padding(.vertical, Spacing.n16)
                .padding(.horizontal, Spacing.n16 + Typography.code.lineBoxInset)
        }
        // Animating the scroll view's resize makes the card jitter as code streams in.
        .transaction { $0.animation = nil }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface.standard.elevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .task(id: request) { await applyHighlighting() }
    }

    /// Selection is enabled once the block is sealed. On a streaming block it would
    /// rebuild selection geometry over the growing text every tick, and there's nothing
    /// to select yet. `highlightSyntax` is false while streaming.
    @ViewBuilder private var codeText: some View {
        let text = Text(highlighted ?? AttributedString(code))
        if highlightSyntax {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    private var request: HighlightRequest {
        HighlightRequest(
            code: code,
            language: highlightSyntax ? language : nil,
            colorScheme: colorScheme
        )
    }

    private func applyHighlighting() async {
        guard let language = request.language, !code.isEmpty else {
            highlighted = nil
            return
        }
        let css = CodeHighlightCSS.stylesheet(for: colors)
        highlighted = try? await sharedHighlighter.attributedText(
            code,
            language: language,
            colors: .custom(css: css)
        )
    }
}

/// Inputs that change the highlighted output. Re-highlighting on anything else
/// would re-run the tokenizer for no visible difference.
private struct HighlightRequest: Equatable {
    let code: String
    /// Nil when the block should render unhighlighted, including when the fence
    /// carries no language: highlight.js guesses poorly on short snippets.
    let language: String?
    let colorScheme: ColorScheme
}

/// One highlighter for the whole app. Each instance carries its own JavaScript
/// context, which is expensive to stand up and to hold open.
private let sharedHighlighter = Highlight()

// MARK: - Previews

private struct CodeBlockPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.n16) {
                EiginCodeBlock(code: Self.swift, language: "swift")
                EiginCodeBlock(code: Self.json, language: "json")
                EiginCodeBlock(code: Self.swift, language: "swift", highlightSyntax: false)
            }
            .padding(Spacing.n24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base)
    }

    static let swift = """
    // A long comment that runs past the card edge to demonstrate horizontal scrolling.
    struct Sightseeing: Activity {
        let name = "Sightseeing"

        func perform(with sloth: inout Sloth) -> Speed {
            sloth.energyLevel -= 10
            return sloth.energyLevel > 0 ? .slow : .stopped
        }
    }
    """

    static let json = #"{ "model": "claude-opus-5", "temperature": 0.7, "stream": true }"#
}

#Preview("Light") {
    CodeBlockPreview()
        .resolveTheme()
}

#Preview("Dark") {
    CodeBlockPreview()
        .resolveTheme()
        .preferredColorScheme(.dark)
}
