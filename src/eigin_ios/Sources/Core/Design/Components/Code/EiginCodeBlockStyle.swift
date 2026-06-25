import SwiftUI
import Textual

/// Renders fenced code blocks as a rounded Eigin card: a token-styled surface with the Fira Code
/// monospace font and horizontal scrolling for long lines.
///
/// Apply it through ``View/eiginStructuredText(colors:highlightSyntax:)`` so every code surface —
/// chat code blocks, the error detail sheet, and the tool detail sheet — shares the same look.
struct EiginCodeBlockStyle: StructuredText.CodeBlockStyle {
    @Environment(\.colors) private var colors

    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .font(Typography.code.font)
                .textual.lineSpacing(.fontScaled(0.1))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Spacing.n16)
                .padding(.horizontal, Spacing.n16)
        }
        .background(colors.surface.standard.elevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .textual.blockSpacing(.fontScaled(top: 0.5, bottom: 0.5))
    }
}

// MARK: - Previews

/// Mirrors real usage: serif prose with the Fira Code card supplied by ``EiginCodeBlockStyle``.
private struct CodeBlockStylePreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            StructuredText(markdown: Self.sample)
                .font(Typography.chatMessage.font)
                .foregroundStyle(colors.text.standard.base)
                .tint(colors.accent)
                .eiginStructuredText(colors: colors)
                .padding(Spacing.n24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base)
    }

    static let sample = """
    Here is some inline `code` inside a sentence, set in Fira Code.

    ```swift
    // A long comment that runs past the card edge to demonstrate horizontal scrolling behaviour.
    struct Sightseeing: Activity {
        let name = "Sightseeing"

        func perform(with sloth: inout Sloth) -> Speed {
            sloth.energyLevel -= 10
            return sloth.energyLevel > 0 ? .slow : .stopped
        }
    }
    ```

    ```json
    { "model": "claude-opus-4-8", "temperature": 0.7, "stream": true }
    ```
    """
}

#Preview("Light") {
    CodeBlockStylePreview()
        .resolveTheme()
}

#Preview("Dark") {
    CodeBlockStylePreview()
        .resolveTheme()
        .preferredColorScheme(.dark)
}
