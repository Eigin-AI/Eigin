import Foundation

/// Parsed markdown documents, keyed by source text.
///
/// Parsing is async, so an unparsed view renders empty and collapses to zero height
/// until it lands. The cache lets a committed message reuse the document streaming
/// already built for it, so it draws at full height on its first frame.
final class MarkdownDocumentCache: @unchecked Sendable {
    static let shared = MarkdownDocumentCache()

    private let storage = NSCache<NSString, Entry>()

    private init() {
        storage.countLimit = 256
    }

    /// The document for `text`, or nil when it hasn't been parsed under `config`.
    /// Styling is baked into a document when it's built, so a config change is a miss.
    func document(
        for text: String,
        config: MarkdownRenderConfig
    ) -> RenderableDocument? {
        guard let entry = storage.object(forKey: text as NSString),
              entry.config == config
        else { return nil }
        return entry.document
    }

    func store(
        _ document: RenderableDocument,
        for text: String,
        config: MarkdownRenderConfig
    ) {
        storage.setObject(Entry(document: document, config: config), forKey: text as NSString)
    }

    /// Parses `texts` into the cache before they're rendered, skipping any already held.
    /// Prewarming a chat before its feed draws means every block opens at its true height
    /// instead of appearing as plain text and resizing.
    func prewarm(_ texts: [String], config: MarkdownRenderConfig) async {
        for text in texts where document(for: text, config: config) == nil {
            await store(parseMarkdownDocument(text, config: config), for: text, config: config)
        }
    }
}

private final class Entry: @unchecked Sendable {
    let document: RenderableDocument
    let config: MarkdownRenderConfig

    init(document: RenderableDocument, config: MarkdownRenderConfig) {
        self.document = document
        self.config = config
    }
}

/// Parses markdown into a document for ``MarkdownBlockView``.
///
/// Speculative rewriting closes partial tables and emphasis, so a table still arriving
/// renders as a table. It's a no-op on complete markdown, so streamed and committed
/// renders share one cache entry.
func parseMarkdownDocument(
    _ text: String,
    config: MarkdownRenderConfig
) async -> RenderableDocument {
    let result = await MarkdownParserImpl().parse(
        text: text,
        option: MarkdownParseOption(speculativeRewrite: true)
    )
    return await RenderableDocument(document: result.document, config: config)
}
