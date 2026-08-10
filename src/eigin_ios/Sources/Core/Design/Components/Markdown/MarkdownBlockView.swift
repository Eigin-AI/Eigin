import SwiftStreamingMarkdown
import SwiftUI

/// Renders a block of markdown in Eigin's styling.
///
/// Parsing is async, so the document comes from ``MarkdownDocumentCache`` when one is
/// ready. That keeps a committed message from flashing empty: streaming parsed these
/// exact blocks moments earlier.
struct MarkdownBlockView: View {
    let text: String

    @Environment(\.markdownRenderConfig) private var config
    @State private var parsed: RenderableDocument?

    var body: some View {
        DocumentView(renderableDocument: document, config: config)
            .task(id: Request(text: text, config: config)) { await load() }
    }

    /// Plain text on a cold mount, not an empty document: an empty one has no height,
    /// so the block collapses and jostles the scroll position until the parse lands.
    private var document: RenderableDocument {
        parsed
            ?? MarkdownDocumentCache.shared.document(for: text, config: config)
            ?? RenderableDocument(plainText: text, config: config)
    }

    private func load() async {
        if let cached = MarkdownDocumentCache.shared.document(for: text, config: config) {
            parsed = cached
            return
        }
        let document = await parseMarkdownDocument(text, config: config)
        MarkdownDocumentCache.shared.store(document, for: text, config: config)
        parsed = document
    }

    /// Everything that changes the parsed output. Re-parsing on anything else
    /// would rebuild the same document.
    private struct Request: Equatable {
        let text: String
        let config: MarkdownRenderConfig
    }
}
