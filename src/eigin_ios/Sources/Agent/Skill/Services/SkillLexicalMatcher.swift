import Foundation

/// Keyword matching over skill metadata, layered under the semantic retrieval
/// in ``SkillIndex``.
///
/// Semantic-only retrieval can't find a skill whose descriptor is sparse —
/// an instruction-less MCP server projects to a boilerplate sentence plus
/// snake_case tool names, so searching "GitLab" missed it (see #317). The
/// matcher scores exact identity and prefix evidence per query part; many
/// tool mentions never stack, so a skill is found by name, not by size.
///
/// Exact name/ID matches (1.0) surface everywhere — search's low bar (0.3)
/// and hints' high bar (0.55). Name-prefix matches (0.6) also clear the hint
/// bar: naming "git" in a message warrants a GitLab hint. Tool-word matches
/// (0.5) are search-only — too incidental to hint from, since long messages
/// mention words like "issue" without wanting a skill.
enum SkillLexicalMatcher {
    /// Prefix matches need at least this many characters ("git" → "gitlab").
    static let minimumPrefixLength = 3

    static let exactNameScore = 1.0
    static let namePrefixScore = 0.6
    static let bodyTokenScore = 0.5

    /// A minimal filler list, not an NLP statement: these few words
    /// otherwise satisfy the ≥3-char prefix rule against real vocabulary.
    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "you", "your", "her", "his",
    ]

    /// A skill's searchable tokens, extracted once per search.
    struct Fields {
        /// Display name tokens, kept in order for phrase matching.
        let nameTokens: [String]
        /// Skill ID tokens (`mcp__gitlab` → `mcp`, `gitlab`), so the `mcp`
        /// marker and sanitized server names stay discoverable.
        let identityTokens: [String]
        /// Everything else searchable: tool-name words and descriptor words.
        let bodyTokens: Set<String>
    }

    /// Lowercased alphanumeric word tokens, dropping short words and fillers.
    static func tokens(_ text: String) -> [String] {
        LexicalTokens.words(text)
            .filter { $0.count >= minimumPrefixLength && !stopwords.contains($0) }
    }

    /// Extracts the searchable fields for one skill.
    static func fields(for skill: Skill) -> Fields {
        let nameTokens = tokens(skill.displayName)
        let identityTokens = tokens(skill.id)
        let toolTokens = skill.requiredTools.flatMap { tokens(lastToolSegment($0.key)) }
        return Fields(
            nameTokens: nameTokens,
            identityTokens: identityTokens,
            bodyTokens: Set(toolTokens + identityTokens + tokens(skill.descriptor))
        )
    }

    /// The best tier `queryParts` (tokenized) earns for `fields`, or `nil`
    /// when no part carries lexical evidence.
    static func score(
        fields: Fields,
        queryParts: [[String]]
    ) -> (score: Double, isExactName: Bool)? {
        var best: (score: Double, isExactName: Bool)?
        for queryTokens in queryParts {
            guard let tier = tier(fields: fields, queryTokens: queryTokens),
                  best == nil || tier.score > best!.score
            else { continue }
            best = tier
        }
        return best
    }

    private static func tier(
        fields: Fields,
        queryTokens: [String]
    ) -> (score: Double, isExactName: Bool)? {
        guard !queryTokens.isEmpty else { return nil }
        if containsPhrase(queryTokens, fields.nameTokens)
            || containsPhrase(queryTokens, fields.identityTokens)
        {
            return (exactNameScore, true)
        }
        if queryTokens.contains(where: { prefixRelated($0, fields.nameTokens) }) {
            return (namePrefixScore, false)
        }
        if queryTokens.contains(where: { prefixRelated($0, fields.bodyTokens) }) {
            return (bodyTokenScore, false)
        }
        return nil
    }

    /// True when the shorter token is a prefix of the other and both are long
    /// enough — "git" matches "gitlab", "issues" matches "issue". Interior
    /// substrings never match, so noise like "iss" can't hit "issue".
    private static func prefixRelated(_ token: String, _ targets: some Sequence<String>) -> Bool {
        for target in targets where min(token.count, target.count) >= minimumPrefixLength {
            if token.hasPrefix(target) || target.hasPrefix(token) { return true }
        }
        return false
    }

    /// Consecutive-equivalent token sequence, so multi-word names
    /// ("Pull Reminders") only match as whole phrases.
    private static func containsPhrase(_ tokens: [String], _ phrase: [String]) -> Bool {
        LexicalTokens.containsPhrase(tokens, phrase)
    }

    /// The tool's own name from a namespaced capability key (`…__list_issues`),
    /// using ``MCPNaming``'s namespace delimiter.
    private static func lastToolSegment(_ key: String) -> String {
        key.components(separatedBy: MCPNaming.namespaceDelimiter).last ?? key
    }
}
