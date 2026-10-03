import Foundation

/// Result of boundary-aware truncation.
struct TruncationResult {
    let text: String
    let truncated: Bool
}

/// Truncated output plus the warnings the tools report to the model.
struct TruncationOutcome {
    let text: String
    let warnings: [String]
}

/// Truncates long output at a structural boundary instead of mid-word.
enum MarkdownTruncation {
    /// Cut at the last blank line (paragraph/heading boundary) before `limit`;
    /// fall back to the last newline, then a word boundary.
    static func truncate(_ text: String, limit: Int) -> TruncationResult {
        guard text.count > limit else { return TruncationResult(text: text, truncated: false) }

        let head = String(text.prefix(limit))

        // Prefer the last blank line; then last newline; then last space.
        if let boundary = head.range(of: "\n\n", options: .backwards)?.upperBound {
            return TruncationResult(
                text: String(text[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines),
                truncated: true
            )
        }
        if let newline = head.lastIndex(of: "\n") {
            return TruncationResult(
                text: String(text[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines),
                truncated: true
            )
        }
        if let space = head.lastIndex(of: " ") {
            return TruncationResult(text: String(text[..<space]), truncated: true)
        }
        return TruncationResult(text: head, truncated: true)
    }

    /// Truncate and produce the standard warning the tools report to the model.
    static func truncateWithWarning(
        _ text: String,
        limit: Int
    ) -> TruncationOutcome {
        let result = truncate(text, limit: limit)
        guard result.truncated else { return TruncationOutcome(text: result.text, warnings: []) }
        return TruncationOutcome(
            text: result.text,
            warnings: ["Content truncated to \(limit) characters."]
        )
    }
}
