import Foundation

/// Surfaces likely mistranscriptions in the latest user message by matching it
/// against the vocabulary — see ``VocabularyMatcher``.
@MainActor
final class VocabularyHintSource: SystemHintSource {
    let title = "Vocabulary hints"

    func render(_ input: SystemHintInput) async -> String? {
        guard input.mode != .text, !input.vocabulary.isEmpty else { return nil }
        guard let said = input.messages.last(where: { $0.role == "user" })?.content else {
            return nil
        }
        let matches = await Task.detached(priority: .userInitiated) {
            // Off-main: bounded but non-trivial for long transcripts.
            VocabularyMatcher.matches(transcript: said, vocabulary: input.vocabulary)
        }.value
        guard !matches.isEmpty else { return nil }

        // Confidence in one character: alias hits are certain (no marker),
        // edit-distance guesses carry "?".
        var lines = [Prompt.Hints.vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)]
        lines.append(contentsOf: matches.map { match in
            "- \(match.said) → \(match.suggestion)\(match.isKnownAlias ? "" : "?")"
        })
        return lines.joined(separator: "\n")
    }
}
