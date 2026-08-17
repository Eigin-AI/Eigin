import SwiftUI
import UIKit

/// Renders an ATX markdown heading in Eigin's title styling. H1 and H2 are uppercased to
/// match the brand's display headings; lower levels keep their case.
///
/// Headings are Eigin's own block, not the markdown library's: the library takes fonts but
/// no text transform, so the uppercasing has to happen here. The styled text renders through
/// the same selectable text view as paragraphs, so headings get the same cursor selection.
struct MarkdownHeadingView: View {
    let level: Int
    let text: String

    @Environment(\.colors) private var colors

    var body: some View {
        ParagraphView(contents: attributedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var uiFont: UIFont {
        switch level {
        case 1: Typography.titleXl.uiFont
        case 2: Typography.titleL.uiFont
        case 3: Typography.titleM.uiFont
        default: Typography.titleS.uiFont
        }
    }

    /// Builds the heading's styled string for the selectable text view: the level's title
    /// font, Eigin's text color, and uppercasing on H1 and H2. Inline bold and italic
    /// resolve against the title font; any inline link keeps its URL.
    private var attributedText: NSMutableAttributedString {
        let baseFont = uiFont
        let color = UIColor(colors.text.standard.base)
        let uppercase = level <= 2
        let parsed = inline(text)
        let result = NSMutableAttributedString()

        for run in parsed.runs {
            var piece = String(parsed[run.range].characters)
            if uppercase { piece = piece.uppercased() }
            let intent = run.inlinePresentationIntent
            var attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont.applying(
                    bold: intent?.contains(.stronglyEmphasized) ?? false,
                    italic: intent?.contains(.emphasized) ?? false
                ),
                .foregroundColor: color,
            ]
            if let url = run.link { attributes[.link] = url }
            result.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return result
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

private extension UIFont {
    /// Returns the font with bold and/or italic traits added, or itself when the family
    /// has no matching variant.
    func applying(bold: Bool, italic: Bool) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
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
