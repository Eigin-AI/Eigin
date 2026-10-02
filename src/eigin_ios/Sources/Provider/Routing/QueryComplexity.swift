import Foundation

/// Scores a user message for how likely it is to need a reasoning model.
///
/// Zero API calls, sub-millisecond, deterministic: weighted keyword and structure
/// signals, plus a "two or more reasoning markers always step up" override that is
/// more language-robust than any single weighted score.
///
/// Keyword tables are per language, and every language's tables are matched against
/// every message — dictation language does not follow the app-language setting, so we
/// score it all. Adding a language means appending tables below, no logic change.
enum QueryComplexity {
    /// A message scoring at or above this warrants a reasoning model. The step-up
    /// cost of a false positive is one slow answer; the flip-flop cost of a false
    /// negative is cache thrash, so the bar sits deliberately low.
    static let threshold = 0.35

    /// Weight of each signal. Agentic work structure ("step one", "then") is the
    /// strongest soft signal for a personal agent; the sum exceeds 1.0 slightly —
    /// the threshold is what matters, not a normalized 0–1 scale.
    private static let weights: [Signal: Double] = [
        .codePresence: 0.30,
        .reasoningMarkers: 0.25,
        .technicalTerms: 0.25,
        .multiStepPatterns: 0.15,
        .tokenCount: 0.10,
        .questionComplexity: 0.10,
        .simpleIndicators: -0.05,
    ]

    /// Reasoning markers needed to step up regardless of the weighted score.
    private static let markersForOverride = 2

    private enum Signal: CaseIterable {
        case codePresence
        case reasoningMarkers
        case technicalTerms
        case tokenCount
        case questionComplexity
        case simpleIndicators
        case multiStepPatterns
    }

    /// Whether the message warrants stepping up to a reasoning model.
    static func needsReasoning(text: String) -> Bool {
        score(text: text) >= threshold || markerCount(in: text) >= markersForOverride
    }

    /// The raw weighted score, exposed for tests and tuning.
    static func score(text: String) -> Double {
        weights.reduce(0.0) { partial, signal in
            partial + signal.value * strength(of: signal.key, in: text)
        }
    }

    /// How strongly one signal fires, in `0...1`.
    private static func strength(of signal: Signal, in text: String) -> Double {
        switch signal {
        case .codePresence:
            return hasAny(QueryComplexityMarkers.codeMarkers, in: text) ? 1 : 0
        case .reasoningMarkers:
            return min(1, Double(markerCount(in: text)) / Double(markersForOverride))
        case .technicalTerms:
            return min(1, Double(matchCount(QueryComplexityMarkers.technicalTerms, in: text)) / 2)
        case .tokenCount:
            return TokenEstimator.estimate(text) > 150 ? 1 : 0
        case .questionComplexity:
            let marks = text.count(where: { $0 == "?" })
            guard marks > 1 else { return 0 }
            return min(1, Double(marks - 1) / 2)
        case .simpleIndicators:
            return hasAny(QueryComplexityMarkers.simpleIndicators, in: text) ? 1 : 0
        case .multiStepPatterns:
            return min(
                1,
                Double(matchCount(QueryComplexityMarkers.multiStepPatterns, in: text)) / 2
            )
        }
    }

    /// Occurrences of reasoning markers in the message. The "two or more"
    /// override is this count, language-robust because it needs only a couple
    /// of signals to fire rather than an exhaustive keyword table.
    static func markerCount(in text: String) -> Int {
        matchCount(QueryComplexityMarkers.reasoningMarkers, in: text)
    }

    /// Number of distinct phrase hits across a table (per occurrence, so repeated
    /// phrasing builds the override count too).
    private static func matchCount(_ phrases: [String], in text: String) -> Int {
        let lowered = text.lowercased()
        return phrases.reduce(0) { $0 + boundedOccurrences($1, in: lowered) }
    }

    private static func hasAny(_ phrases: [String], in text: String) -> Bool {
        let lowered = text.lowercased()
        return phrases.contains { boundedOccurrences($0, in: lowered) > 0 }
    }

    /// How many times `phrase` occurs in `lowered` text, letter-bounded on both
    /// ends. Substring matching would smuggle markers inside longer words — "hi"
    /// inside "while", "tak" inside "take", "analyse" inside "analyser" — so
    /// markers must not touch a letter on either side. Multi-word phrases only
    /// ever match with spaces around them, which satisfies the rule for free.
    private static func boundedOccurrences(_ phrase: String, in lowered: String) -> Int {
        let firstIsLetter = phrase.first?.isLetter ?? false
        let lastIsLetter = phrase.last?.isLetter ?? false
        var count = 0
        var searchStart = lowered.startIndex
        while let range = lowered.range(of: phrase, range: searchStart ..< lowered.endIndex) {
            // Only a phrase that ends in a letter can be part of a longer word.
            let touchesLetterBefore = firstIsLetter
                && range.lowerBound > lowered.startIndex
                && lowered[lowered.index(before: range.lowerBound)].isLetter
            let touchesLetterAfter = lastIsLetter
                && range.upperBound < lowered.endIndex
                && lowered[range.upperBound].isLetter
            if !touchesLetterBefore, !touchesLetterAfter { count += 1 }
            searchStart = range.upperBound
        }
        return count
    }
}
