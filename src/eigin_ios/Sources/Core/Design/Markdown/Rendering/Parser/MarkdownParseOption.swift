/// Options that control how a `MarkdownParser` processes input text.
struct MarkdownParseOption {
    /// Whether to speculatively rewrite markdown that looks incomplete (a string
    /// ending mid-table or mid-emphasis), so a streaming message doesn't flash
    /// broken syntax while it's still arriving.
    ///
    /// No default: callers state it explicitly. `MarkdownDocumentCache` (the chat
    /// rendering path) turns it on, since messages arrive incomplete mid-stream.
    /// `MarkdownParser.parse(text:)`'s convenience overloads turn it off, since
    /// they assume the text they're given is already complete.
    let speculativeRewrite: Bool

    /// Specify how to parse latex
    let latexMatchingRules: [LatexMatching]

    /// Create a new parse option.
    /// - Parameters:
    ///   - speculativeRewrite: See `speculativeRewrite`.
    ///   - latexMatchingRules: See `latexMatchingRules`. Defaults to every supported rule.
    init(
        speculativeRewrite: Bool,
        latexMatchingRules: [LatexMatching] = LatexMatching.allCases
    ) {
        self.speculativeRewrite = speculativeRewrite
        self.latexMatchingRules = latexMatchingRules
    }

    /// The set of delimiter forms the LaTeX preprocessor will recognize. Omitting
    /// a case leaves text matching that delimiter as plain markdown.
    enum LatexMatching: String, Hashable, CaseIterable {
        /// Inline LaTeX delimited by `\(` … `\)`.
        case inlineSlashBracket
        /// Block LaTeX delimited by `$$` … `$$`.
        case blockDollar
        /// Block LaTeX delimited by `\[` … `\]`.
        case blockSlashBracket
    }
}
