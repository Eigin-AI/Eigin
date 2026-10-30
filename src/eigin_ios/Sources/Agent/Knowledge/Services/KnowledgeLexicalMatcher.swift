import Foundation

/// Lexical evidence for knowledge retrieval, independent of memory history.
enum KnowledgeLexicalMatcher {
    static let qualifiedIDScore = 2.2
    static let exactIDScore = 2.0
    static let exactNameScore = 1.8
    static let identityPhraseScore = 1.6
    static let fullCoverageScore = 1.2

    /// Prepares a query once for the candidate scan.
    struct Query {
        let tokens: [String]
        let normalizedID: String

        init(_ text: String) {
            tokens = LexicalTokens.words(text)
            normalizedID = FirmIDNormalization
                .normalize(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Scores identity separately from descriptive text and relationship mentions.
    static func score(entity: FirmEntity, qualifiedID: String, query: Query) -> Double {
        let tokens = query.tokens
        guard !tokens.isEmpty else { return 0 }
        if query.normalizedID == FirmIDNormalization
            .normalize(qualifiedID) { return qualifiedIDScore }
        let shortID = knowledgeShortID(from: entity.id, type: entity.entityType)
        if query.normalizedID == FirmIDNormalization.normalize(shortID) { return exactIDScore }
        let shortTokens = LexicalTokens.words(shortID)

        var allTokens = Set(shortTokens)
        var identityPhrase = LexicalTokens.containsPhrase(shortTokens, tokens)
        for field in entity.fields {
            let values = textValues(field.value)
            for value in values {
                let words = LexicalTokens.words(value)
                if field.name == "name" || field.name == "title" {
                    if words == tokens { return exactNameScore }
                    identityPhrase = identityPhrase || LexicalTokens.containsPhrase(words, tokens)
                }
                allTokens.formUnion(words)
            }
        }
        if identityPhrase { return identityPhraseScore }
        let matched = tokens.count(where: { allTokens.contains($0) })
        if matched == tokens.count { return fullCoverageScore }
        // Prefix evidence is weak and must cover each token independently.
        let prefixMatched = tokens.count(where: { token in
            allTokens.contains(token) || (token.count >= 4 && allTokens.contains {
                min($0.count, token.count) >= 4 && ($0.hasPrefix(token) || token.hasPrefix($0))
            })
        })
        if prefixMatched == tokens.count { return 0.6 }
        return 0.4 * Double(prefixMatched) / Double(tokens.count)
    }

    private static func textValues(_ value: FirmFieldValue) -> [String] {
        switch value {
        case .string(let text), .enum(let text), .entityReference(let text): [text]
        case .list(let values): values.flatMap { textValues($0) }
        default: []
        }
    }
}
