import Markdown

/// The built-in `MarkdownParser` implementation.
final class MarkdownParserImpl: MarkdownParser {
    private let rewriters: [MarkupPostParsingRewriter] = [
        PartialStrongMarkupPostParsingRewriter(),
        PartialTableMarkupPostParsingRewriter(),
    ]

    private let latexPreprocessor: LaTexPreProcessor

    /// Create a new parser instance using the default LaTeX preprocessor.
    init() {
        latexPreprocessor = LaTexPreProcessorImpl()
    }

    /// Parse `text` into a `MarkdownParseResult`. See `MarkdownParser.parse(text:option:)`.
    func parse(text: String, option: MarkdownParseOption) async -> MarkdownParseResult {
        let targetString = latexPreprocessor.process(
            input: text,
            matchingRules: option.latexMatchingRules
        )

        var result = MarkdownParseResult(
            document: Document(parsing: targetString),
            speculativeRewritten: false
        )

        if option.speculativeRewrite {
            for rewriter in rewriters {
                if let rewrittenDoc = rewriter.rewriteIfApplicable(document: result.document) {
                    result = MarkdownParseResult(document: rewrittenDoc, speculativeRewritten: true)
                }
            }
        }

        return result
    }
}
