import Foundation

/// Policy-free normalization shared by lexical search matchers.
enum LexicalTokens {
    /// Case-insensitive words, treating punctuation and ID separators as boundaries.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Whether the ordered phrase occurs at token boundaries.
    static func containsPhrase(_ tokens: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return false }
        return (0 ... (tokens.count - phrase.count)).contains { start in
            tokens[start ..< start + phrase.count].elementsEqual(phrase)
        }
    }
}
