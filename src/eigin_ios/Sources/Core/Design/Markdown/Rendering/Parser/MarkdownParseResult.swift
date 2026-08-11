import Markdown

/// The output of `MarkdownParser.parse(text:option:)`.
struct MarkdownParseResult {
    /// The parsed markdown `Document` tree.
    let document: Document
    /// `true` if the parser applied a speculative rewrite (e.g. completing a
    /// partial table or emphasis) before returning the document.
    let speculativeRewritten: Bool
}
