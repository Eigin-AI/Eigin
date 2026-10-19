import Foundation
import SwiftUI

struct OrderedListView: View {
    let items: [MarkdownListItem]
    let nestedLevel: Int
    @Environment(\.markdownConfig) var config: MarkdownRenderConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8, content: {
            ForEach(0 ..< items.count, id: \.self) { idx in
                HStack(alignment: .centerOfFirstLine, spacing: 11) {
                    Text(verbatim: "\(idx + 1).")
                        .font(config.orderedListStyle.textFonts, bold: true)
                        .foregroundStyle(config.orderedListStyle.textColor)
                        .transition(.opacity)
                    if let firstChild = items[idx].children.first {
                        if case .paragraph(_, let contents) = firstChild {
                            // Wrap the SingleBlockView to provide proper baseline alignment. This
                            // is to fix the mis-alignment when the view is rendered off-screen,
                            // e.g. snapshot.
                            ListItemContentWrapper(paragraphContents: contents) {
                                SingleBlockView(renderable: firstChild)
                            }
                            .accessibilityLabel(Text(markdownListAccessibilityLabel(
                                for: contents.string,
                                at: idx,
                                length: items.count
                            )))
                        } else {
                            SingleBlockView(renderable: firstChild)
                        }
                    }
                    Spacer()
                }
                if items[idx].children.count > 1 {
                    BlockView(renderables: Array(items[idx].children.dropFirst()))
                        .padding([.leading], 0)
                }
            }
        })
        .padding([.leading], CGFloat(nestedLevel) * 8)
    }
}

/// Wrapper to provide proper baseline alignment for UIViewRepresentable content
struct ListItemContentWrapper<Content: View>: View {
    let paragraphContents: NSMutableAttributedString
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Resolve the line box on the main actor here so the alignment guide closure
        // captures only a plain CGFloat.
        let lineHeight = paragraphContents.leadingTextFonts?.preferredLineHeight
        let firstLineCenter = (lineHeight ?? extractFirstFont().lineHeight) / 2.0
        content()
            .alignmentGuide(.centerOfFirstLine) { _ in firstLineCenter }
    }

    private func extractFirstFont() -> MDFont {
        if let font = firstFont(in: paragraphContents) {
            return font
        }
        return MDFont.preferredFont(forTextStyle: .body)
    }

    private func firstFont(in attributedString: NSAttributedString) -> MDFont? {
        guard attributedString.length > 0 else { return nil }

        // Fast path: attribute at location 0
        if let font = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? MDFont {
            return font
        }

        var found: MDFont?
        attributedString.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            if let font = value as? MDFont {
                found = font
                stop.pointee = true
            }
        }
        return found
    }
}

func markdownListAccessibilityLabel(
    for item: String,
    at index: Int,
    length: Int
) -> String {
    String.markdownListItem(length: length, index: index + 1, item: item)
}

#Preview(body: {
    let items: [MarkdownListItem] = (0 ..< 40).map { i in
        MarkdownListItem(
            children: [.paragraph(
                id: "\(i)",
                content: NSMutableAttributedString(string: "item \(i + 1)")
            )],
            startsWithBold: false
        )
    }
    return ScrollView {
        OrderedListView(items: items, nestedLevel: 0)
    }
})
