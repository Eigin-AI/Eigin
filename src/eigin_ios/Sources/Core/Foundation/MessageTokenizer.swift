import Foundation
import NaturalLanguage

/// Shared word-tokenisation for lightweight, language-agnostic message matching
/// (knowledge name-mentions, skill trigger keywords).
enum MessageTokenizer {
    /// Default minimum token length — filters tiny function words and punctuation
    /// artefacts while still catching short names ("Bob", "Ada").
    static let defaultMinTokenLength = 3

    /// Tokenises `text` into lowercased, letters-only words at least `minLength` long,
    /// via `NLTokenizer` so language-specific word boundaries are respected.
    nonisolated static func tokenize(
        _ text: String, minLength: Int = defaultMinTokenLength
    ) -> Set<String> {
        var tokens = Set<String>()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let raw = String(text[range]).lowercased()
            if raw.count >= minLength, raw.allSatisfy(\.isLetter) {
                tokens.insert(raw)
            }
            return true
        }
        return tokens
    }
}
