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
    /// While streaming, code renders unhighlighted and unselectable: highlighting
    /// round-trips through an HTML parse, too expensive to repeat per chunk, and
    /// selection over growing text would rebuild its geometry on every tick.
    var isStreaming: Bool = false

    @Environment(\.colors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @State private var highlighted: AttributedString?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            CodeTextView(attributedText: attributedCode, isSelectable: !isStreaming)
                .offset(y: Typography.code.textKitShift)
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

    /// Font, plain color and line height: the styling for unhighlighted code, and the
    /// defaults filled in under the highlighter's token colors once it's sealed.
    private var defaultCodeAttributes: [NSAttributedString.Key: Any] {
        var attributes = Typography.code.textAttributes
        attributes[.foregroundColor] = UIColor(colors.code.plain)
        return attributes
    }

    /// Builds the rendered string: uniform attributes while streaming, or the
    /// highlighter's output with the defaults layered underneath once sealed.
    private var attributedCode: NSAttributedString {
        let attributes = defaultCodeAttributes
        guard let highlighted else {
            return NSAttributedString(string: code, attributes: attributes)
        }

        let base = NSMutableAttributedString(highlighted)
        let whole = NSRange(location: 0, length: base.length)
        base.addAttribute(.font, value: Typography.code.uiFont, range: whole)
        base.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            if value == nil {
                base.addAttribute(
                    .foregroundColor,
                    value: attributes[.foregroundColor]!,
                    range: range
                )
            }
        }
        if let paragraphStyle = attributes[.paragraphStyle] {
            base.addAttribute(.paragraphStyle, value: paragraphStyle, range: whole)
        }
        return base
    }

    private var request: HighlightRequest {
        HighlightRequest(
            code: code,
            language: isStreaming ? nil : language,
            colorScheme: colorScheme
        )
    }

    private func applyHighlighting() async {
        guard let language = request.language, !code.isEmpty else {
            highlighted = nil
            return
        }
        let css = CodeHighlightCSS.stylesheet(for: colors)
        highlighted = await HighlightQueue.shared.attributedText(
            code,
            language: language,
            css: css
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

// MARK: - Previews

private struct CodeBlockPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.n16) {
                EiginCodeBlock(code: Self.swift, language: "swift")
                EiginCodeBlock(code: Self.json, language: "json")
                EiginCodeBlock(code: Self.swift, language: "swift", isStreaming: true)
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
