import SwiftUI

/// Renders an ATX markdown heading in Eigin's title styling. H1 and H2 are uppercased to
/// match the brand's display headings; lower levels keep their case.
///
/// Headings are Eigin's own block, not the markdown library's: the library takes fonts but
/// no text transform, so the uppercasing has to happen here, at the render layer, where it
/// leaves any inline link's URL untouched.
struct MarkdownHeadingView: View {
    let level: Int
    let text: String

    @Environment(\.colors) private var colors

    var body: some View {
        Text(inline(text))
            .font(font)
            .textCase(level <= 2 ? .uppercase : nil)
            .foregroundStyle(colors.text.standard.base)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var font: Font {
        switch level {
        case 1: Typography.titleXl.font
        case 2: Typography.titleL.font
        case 3: Typography.titleM.font
        default: Typography.titleS.font
        }
    }

    /// Headings carry inline markdown only; bold and italic resolve against the title font.
    private func inline(_ markdown: String) -> AttributedString {
        (
            try? AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        ) ?? AttributedString(markdown)
    }
}

// MARK: - Previews

private struct HeadingPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.n16) {
                MarkdownHeadingView(level: 1, text: "The quiet heading")
                MarkdownHeadingView(level: 2, text: "A second level")
                MarkdownHeadingView(level: 3, text: "Third level keeps its case")
                MarkdownHeadingView(level: 4, text: "Fourth with **bold** inside")
            }
            .padding(Spacing.n24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base)
    }
}

#Preview("Light") {
    HeadingPreview()
        .resolveTheme()
}

#Preview("Dark") {
    HeadingPreview()
        .resolveTheme()
        .preferredColorScheme(.dark)
}
