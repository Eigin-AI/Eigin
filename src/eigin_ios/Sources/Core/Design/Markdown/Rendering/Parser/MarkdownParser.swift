import Markdown

/// Parse a given text into a markdown tree, represented by `Document`
protocol MarkdownParser {
    /// Perform the parsing
    /// - Parameter text: The incoming text
    /// - Parameter option: The option for parsing
    /// - Returns: The parse result
    func parse(text: String, option: MarkdownParseOption) async -> MarkdownParseResult
}

extension MarkdownParser {
    /// Convenience overload that parses `text` with all options disabled and
    /// returns only the parsed `Document`.
    /// - Parameter text: The incoming text
    /// - Returns: The parsed markdown `Document` tree
    func parse(text: String) async -> Document {
        await parse(text: text, option: .init(speculativeRewrite: false)).document
    }

    /// Convenience overload that parses `text` and produces a fully laid-out
    /// `RenderableDocument` ready to hand to `DocumentView`.
    /// - Parameters:
    ///   - text: The incoming text.
    ///   - config: Render configuration applied when building the renderable.
    /// - Returns: A `RenderableDocument` built from the parsed `Document`.
    func parse(text: String, config: MarkdownRenderConfig) async -> RenderableDocument {
        let document = await parse(
            text: text,
            option: .init(speculativeRewrite: false)
        ).document
        return await RenderableDocument(document: document, config: config)
    }
}
