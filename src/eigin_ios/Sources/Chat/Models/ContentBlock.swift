import Foundation

struct ContentBlock: Identifiable, Equatable {
    let id: String
    let kind: BlockKind
    var text: String
    var language: String?
}

enum BlockKind: Equatable {
    case paragraph
    case code
    case table
    case math
    case list
    case divider
    case heading(level: Int)
    case image(src: String, alt: String?, href: String?)

    /// Whether the shared markdown renderer draws this kind. Code, tables, dividers,
    /// headings, math and images have their own Eigin views.
    var usesMarkdownRenderer: Bool {
        switch self {
        case .paragraph, .list: true
        case .code, .table, .divider, .heading, .math, .image: false
        }
    }
}

extension ContentBlock {
    /// Splits raw chat markdown into renderable blocks, one pass, line-based.
    /// While `isStreaming`, text that opens a construct but hasn't closed it —
    /// a code fence, an image card — is held back until it closes; anything
    /// proven not to be one comes back as prose.
    static func split(
        _ text: String,
        messageID: String,
        isStreaming: Bool = false
    ) -> [ContentBlock] {
        guard !text.isEmpty else { return [] }
        var splitter = BlockSplitter(messageID: messageID, isStreaming: isStreaming)
        return splitter.scan(text)
    }
}
