import Foundation
import Markdown
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A `MarkdownRenderConfig`-aware snapshot of a parsed markdown `Document`,
/// ready to be handed to a `MarkdownView` for rendering. Producing one is
/// the heavyweight step; rendering it is cheap.
struct RenderableDocument: Equatable, Sendable {
    let renderables: [MarkdownRenderable]

    var containsCodeBlock: Bool {
        renderables.contains(where: { $0.isCodeBlock })
    }

    var containsBlockQuote: Bool {
        renderables.contains(where: { $0.isBlockQuote })
    }

    var isEmpty: Bool {
        renderables.isEmpty
    }

    /// Convert a parsed `Document` into a `RenderableDocument` using the supplied config.
    /// - Parameters:
    ///   - document: The parsed markdown tree.
    ///   - config: Styling and behavior used during conversion.
    init(document: Markdown.Document, config: MarkdownRenderConfig) async {
        renderables = document.convert(with: config)
    }

    /// Construct a renderable wrapping a single plain-text paragraph styled
    /// with `config.paragraphStyle`. Useful for showing non-markdown text in a
    /// `MarkdownView` without round-tripping through the parser.
    init(plainText: String, config: MarkdownRenderConfig) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: config.paragraphStyle.textFonts.normal,
            .foregroundColor: MDColor(config.paragraphStyle.textColor),
        ]
        if let kern = config.paragraphStyle.textFonts.preferredLetterSpacing {
            attributes[.kern] = kern
        }
        let content = NSMutableAttributedString(string: plainText, attributes: attributes)
        self.init(renderables: [.paragraph(id: UUID().uuidString, content: content)])
    }

    init(renderables: [MarkdownRenderable]) {
        self.renderables = renderables
    }

    /// An empty document, equivalent to `RenderableDocument(plainText: "", …)`
    /// but allocation-free.
    static let empty = RenderableDocument(renderables: [])
}

extension RenderableDocument {
    var attributedStrings: [NSAttributedString] {
        renderables.flatMap { $0.extractAttributedStrings() }
    }

    /// The full document rendered as plain text, across every block kind
    /// (headings, paragraphs, lists, code blocks, tables, block quotes). Used to
    /// populate the "Select more text" modal.
    var plainText: String {
        renderables
            .compactMap { $0.plainText }
            .joined(separator: "\n\n")
    }
}

extension MarkdownRenderable {
    /// A plain-text representation of this block, or `nil` for blocks that carry
    /// no selectable text (e.g. thematic breaks).
    var plainText: String? {
        switch self {
        case .paragraph(_, let content), .heading(_, _, let content):
            return content.string
        case .latex(_, let content):
            return content
        case .orderedList(_, let items, _):
            return items.plainText(separator: "\n")
        case .unorderedList(_, let items, _):
            return items.plainText(separator: "\n")
        case .codeBlock(_, _, let code):
            return code
        case .table(_, let headers, let rows, _):
            let headerLine = headers.map { $0.string }.joined(separator: "\t")
            let rowLines = rows.map { row in row.map { $0.string }.joined(separator: "\t") }
            return ([headerLine] + rowLines).joined(separator: "\n")
        case .blockQuote(_, let children):
            let lines = children.compactMap { $0.plainText }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        case .thematicBreak:
            return nil
        }
    }
}

private extension [MarkdownListItem] {
    func plainText(separator: String) -> String? {
        let lines = flatMap { item in
            item.children.compactMap { $0.plainText }
        }
        return lines.isEmpty ? nil : lines.joined(separator: separator)
    }
}

extension MarkdownRenderable {
    func extractAttributedStrings() -> [NSAttributedString] {
        switch self {
        case .paragraph(_, let str):
            [str]
        case .orderedList(_, let items, _):
            items.flatMap { $0.attributedStrings() }
        case .unorderedList(_, let items, _):
            items.flatMap { $0.attributedStrings() }
        case .table(_, let headers, let rows, _):
            headers + rows.flatMap { $0 }
        case .blockQuote(_, let children):
            children.flatMap { $0.extractAttributedStrings() }
        default:
            []
        }
    }
}

extension MarkdownListItem {
    func attributedStrings() -> [NSAttributedString] {
        children.flatMap { $0.extractAttributedStrings() }
    }
}
