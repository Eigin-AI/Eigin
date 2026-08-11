import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Markdown element representation that is ready to be rendered by a SwiftUI View
/// The representation already have all the parsing and processing completed to minimize rendering
/// overhead on UI thread.
/// This data structure is not thread safe due to the usage of `NSMutableAttributedString`, this
/// needs to be addressed as a future improvement
indirect enum MarkdownRenderable: Identifiable, Equatable, @unchecked Sendable {
    /// To be rendered as a paragraph
    case paragraph(id: String, content: NSMutableAttributedString)

    /// To be rendered as LaTeX (Math formatting)
    case latex(id: String, content: String)

    /// To be rendered as a heading
    case heading(id: String, level: Int, content: NSMutableAttributedString)

    /// To be rendered as a ordered list view
    case orderedList(id: String, items: [MarkdownListItem], nestedLevel: Int)

    /// To be rendered as an unordered list
    case unorderedList(id: String, items: [MarkdownListItem], nestedLevel: Int)

    /// To be rendered as a code block
    case codeBlock(id: String, language: String?, code: String)

    /// To be rendered as a table
    case table(
        id: String,
        headers: [NSMutableAttributedString],
        rows: [[NSMutableAttributedString]],
        rawMarkdown: String
    )

    /// To be rendered as thematic break
    case thematicBreak(id: String)

    /// To be rendered as a block quote: any nested block content (paragraphs,
    /// lists, nested quotes, ...) drawn behind a leading bar.
    case blockQuote(id: String, children: [MarkdownRenderable])

    var id: String {
        switch self {
        case .paragraph(let id, _): id
        case .latex(let id, _): id
        case .heading(let id, _, _): id
        case .orderedList(let id, _, _): id
        case .unorderedList(let id, _, _): id
        case .codeBlock(let id, _, _): id
        case .table(let id, _, _, _): id
        case .thematicBreak(let id): id
        case .blockQuote(let id, _): id
        }
    }

    var isCodeBlock: Bool {
        switch self {
        case .codeBlock: true
        default: false
        }
    }

    var isBlockQuote: Bool {
        switch self {
        case .blockQuote: true
        default: false
        }
    }
}

struct MarkdownListItem: Equatable {
    /// Checkbox state for a GitHub-flavored task list item (`- [ ]` / `- [x]`).
    enum Checkbox {
        case checked
        case unchecked
    }

    let children: [MarkdownRenderable]
    let startsWithBold: Bool
    /// `nil` for regular list items.
    let checkbox: Checkbox?

    init(children: [MarkdownRenderable], startsWithBold: Bool, checkbox: Checkbox? = nil) {
        self.children = children
        self.startsWithBold = startsWithBold
        self.checkbox = checkbox
    }
}
