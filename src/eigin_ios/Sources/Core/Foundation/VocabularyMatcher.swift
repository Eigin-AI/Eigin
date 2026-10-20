import Foundation

/// Fuzzy-matches transcribed text against the vocabulary to surface likely
/// mistranscriptions as hint candidates — see ``VocabularyHintSource``.
///
/// Two passes, both cheap:
/// 1. Literal hits on known-mistranscription aliases (case/diacritic
///    normalization only) — high confidence.
/// 2. Edit distance against canonical words — close misses like
///    "Eigen"→"Eigin", threshold scaled by word length.
///
/// Exact hits on canonical words are skipped: those transcribed fine.
enum VocabularyMatcher: Sendable {
    struct Match: Equatable, Sendable {
        /// The transcribed word(s) that look like a mistranscription.
        let said: String
        /// The vocabulary word they likely mean.
        let suggestion: String
        /// `true` when `said` is a recorded alias (literal hit) rather than an
        /// edit-distance guess.
        let isKnownAlias: Bool
    }

    /// Upper bound on matches rendered into a single hint.
    static let matchLimit = 3

    static func matches(transcript: String, vocabulary: [VocabularyEntry]) -> [Match] {
        let tokens = tokenize(transcript)
        guard !tokens.isEmpty else { return [] }

        var best: [String: Match] = [:] // suggestion word -> best match found
        for entry in vocabulary {
            guard let match = bestMatch(in: tokens, for: entry) else { continue }
            if let current = best[entry.word] {
                // Alias hits outrank distance hits; otherwise lower distance wins.
                if match.isKnownAlias, !current.isKnownAlias {
                    best[entry.word] = match
                }
            } else {
                best[entry.word] = match
            }
        }

        let matches = Array(best.values.map(\.self))
        return Array(matches
            .sorted { lhs, rhs in
                if lhs.isKnownAlias != rhs.isKnownAlias { return lhs.isKnownAlias }
                if lhs.said.count != rhs.said.count { return lhs.said.count < rhs.said.count }
                return lhs.said < rhs.said
            }
            .prefix(matchLimit))
    }

    // MARK: - Per-entry matching

    /// Best match for one entry across its aliases (literal) and the canonical
    /// word (edit distance), or nil when nothing is close enough.
    private static func bestMatch(
        in tokens: [(raw: String, norm: String)], for entry: VocabularyEntry
    ) -> Match? {
        var best: (match: Match, distance: Int)?

        // Alias pass: literal equality (normalized) for each alias.
        for alias in entry.aliases {
            let aliasNorm = normalized(alias)
            for window in windows(
                in: tokens,
                ofLength: max(1, aliasNorm.split(separator: " ").count)
            )
                where window.norm == aliasNorm
            {
                consider((
                    Match(said: window.raw, suggestion: entry.word, isKnownAlias: true), 0
                ), into: &best)
            }
        }
        if best?.match.isKnownAlias == true { return best?.match }

        // Edit-distance pass against the canonical word. Multi-token windows
        // only fire on exact spelled-out joins ("a k q a" → "AKQA"); looser
        // multi-token thresholds would fire on ordinary prose joins like
        // "at last" → "Atlas".
        let candidate = normalized(entry.word)
        let noSpace = candidate.replacingOccurrences(of: " ", with: "")
        let entryTokenCount = max(1, entry.word.split(separator: " ").count)
        for length in 1 ... min(tokens.count, entryTokenCount + 3) {
            for window in windows(in: tokens, ofLength: length) {
                var distance = levenshtein(window.norm, candidate)
                if length > 1 {
                    // Join check compares the space-stripped window.
                    let stripped = window.norm.replacingOccurrences(of: " ", with: "")
                    distance = min(distance, stripped == noSpace ? 0 : Int.max)
                }
                // Single tokens at distance 0 transcribed fine; multi-token
                // distance-0 joins are spelled-out words worth hinting.
                guard distance > 0 || length > 1,
                      isWithinThreshold(distance: distance, wordLength: noSpace.count)
                else { continue }
                consider((
                    Match(said: window.raw, suggestion: entry.word, isKnownAlias: false), distance
                ), into: &best)
            }
        }

        return best?.match
    }

    /// Keeps the better candidate: alias hits over distance hits, then lower
    /// distance; ties keep the earlier match.
    private static func consider(
        _ candidate: (match: Match, distance: Int),
        into best: inout (match: Match, distance: Int)?
    ) {
        guard let current = best else {
            best = candidate
            return
        }
        if candidate.match.isKnownAlias != current.match.isKnownAlias {
            if candidate.match.isKnownAlias { best = candidate }
            return
        }
        if candidate.distance < current.distance { best = candidate }
    }

    /// All contiguous n-token windows, raw text joined with spaces and the
    /// normalized forms joined with spaces ("a k q a" style spacing handled).
    private static func windows(
        in tokens: [(raw: String, norm: String)], ofLength count: Int
    ) -> [(raw: String, norm: String)] {
        guard count >= 1, tokens.count >= count else { return [] }
        return (0 ... tokens.count - count).map { start in
            let slice = Array(tokens[start ..< start + count])
            return (
                raw: slice.map(\.raw).joined(separator: " "),
                norm: slice.map(\.norm).joined(separator: " ")
            )
        }
    }

    /// Length-scaled Levenshtein budget: short words must match exactly,
    /// medium words allow one edit, long words allow two.
    private static func isWithinThreshold(distance: Int, wordLength: Int) -> Bool {
        switch wordLength {
        case ..<4: distance <= 0
        case ..<7: distance <= 1
        default: distance <= 2
        }
    }

    // MARK: - Text normalization

    /// Lowercased, diacritic-free copy with surrounding punctuation trimmed.
    private static func normalized(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
    }

    /// Splits the transcript into raw/normalized token pairs, dropping empties.
    private static func tokenize(_ transcript: String) -> [(raw: String, norm: String)] {
        transcript
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .compactMap { raw in
                let rawWord = String(raw)
                let norm = normalized(rawWord)
                return norm.isEmpty ? nil : (raw: rawWord, norm: norm)
            }
    }

    // MARK: - Edit distance

    /// Classic Levenshtein distance; inputs are single words, so this is cheap.
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let lhs = Array(a)
        let rhs = Array(b)
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0 ... rhs.count)
        for (i, l) in lhs.enumerated() {
            var current = [i + 1]
            for (j, r) in rhs.enumerated() {
                let substitution = previous[j] + (l == r ? 0 : 1)
                current.append(min(current[j] + 1, previous[j + 1] + 1, substitution))
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
