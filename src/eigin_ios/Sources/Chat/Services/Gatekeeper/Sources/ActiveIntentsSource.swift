import Foundation

/// Renders the agent's currently active intents (goals it's pursuing).
///
/// Stateless. Intents arrive ordered by temporal relevance from
/// ``IntentService``; this source formats each as a single compact line — a
/// one-sentence summary, a timeliness cue, and the next open action — so the
/// hint stays digest-sized. Full detail and ids stay behind `list_intents`,
/// cued by a footer line in full-context mode. Small-context models get the
/// same line format truncated to the top three intents.
@MainActor
final class ActiveIntentsSource: SystemHintSource {
    let title = "Active intents"

    /// Maximum number of intents rendered in compact mode.
    private let compactLimit = 3
    /// Character cap applied to each intent's summary line.
    private let summaryLimit = 90
    /// Character cap applied to the next-action clause.
    private let nextActionLimit = 50

    func render(_ input: SystemHintInput) async -> String? {
        guard !input.activeIntents.isEmpty else { return nil }

        let intents = input.isSmallContext
            ? Array(input.activeIntents.prefix(compactLimit))
            : input.activeIntents

        var lines = intents.map { line(for: $0) }
        if !input.isSmallContext {
            lines.append(Prompt.Hints.activeIntentsFooter
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Line rendering

    private func line(for intent: IntentSnapshot) -> String {
        var line = "- \(Self.summary(intent.content, limit: summaryLimit))"
        if let cue = IntentDigest.summary(for: intent) {
            line += " (\(cue))"
        }
        if let next = nextAction(for: intent) {
            line += ". Next: \(next)"
        }
        return line
    }

    /// First sentence of the intent's content, capped and ellipsized.
    ///
    /// A multi-sentence paragraph collapses to its first sentence even when the
    /// whole content would fit; mid-sentence truncation is only a fallback.
    /// Whitespace (including newlines) is collapsed so the summary stays one
    /// hint line.
    static func summary(_ content: String, limit: Int) -> String {
        let trimmed = Self.collapsedWhitespace(in: content)

        let terminators: Set<Character> = [".", "!", "?"]
        if let firstTerminator = trimmed.firstIndex(where: { terminators.contains($0) }) {
            let sentence = String(trimmed[...firstTerminator])
            if sentence.count < trimmed.count, sentence.count <= limit {
                return sentence
            }
        }
        guard trimmed.count > limit else { return trimmed }

        // Long single sentence: cut at the first clause dash before falling
        // back to a hard prefix. The clause stands alone as a compact label.
        if let dash = trimmed.firstIndex(of: "—") {
            let clause = String(trimmed[..<dash]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clause.isEmpty, clause.count <= limit {
                return clause
            }
        }
        return String(trimmed.prefix(limit)) + "…"
    }

    /// The first pending task's content, or nil when nothing is left to do.
    private func nextAction(for intent: IntentSnapshot) -> String? {
        guard let task = intent.tasks.first(where: { !$0.completed }) else { return nil }
        let content = Self.collapsedWhitespace(in: task.content)
        guard content.count > nextActionLimit else { return content }
        return String(content.prefix(nextActionLimit)) + "…"
    }

    /// Trims the ends and collapses internal whitespace runs to single spaces.
    private static func collapsedWhitespace(in text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
