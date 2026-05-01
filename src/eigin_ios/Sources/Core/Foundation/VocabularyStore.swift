import Factory
import Foundation

/// Manages a vocabulary list that feeds into speech recognition contextual strings.
protocol VocabularyStore: Sendable {
    /// Returns built-in words + agent name + user words, deduplicated.
    func allWords(agentName: String) -> [String]
    /// Returns just user-managed words.
    func userWords() -> [String]
    func addWords(_ words: [String])
    func removeWords(_ words: [String])
}

final class DefaultVocabularyStore: VocabularyStore {
    static let builtInWords = ["Eigin"]

    private static let defaultsKey = "vocabulary"
    private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func allWords(agentName: String) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for word in Self.builtInWords + [agentName] + userWords() {
            let trimmed = word.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    func userWords() -> [String] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let words = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return words
    }

    func addWords(_ words: [String]) {
        var current = Set(userWords())
        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { current.insert(trimmed) }
        }
        save(Array(current).sorted())
    }

    func removeWords(_ words: [String]) {
        let toRemove = Set(words.map { $0.trimmingCharacters(in: .whitespaces) })
        let filtered = userWords().filter { !toRemove.contains($0) }
        save(filtered)
    }

    private func save(_ words: [String]) {
        guard let data = try? JSONEncoder().encode(words) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Preview stub — returns empty vocabulary.
struct PreviewVocabularyStore: VocabularyStore {
    func allWords(agentName: String) -> [String] {
        []
    }

    func userWords() -> [String] {
        []
    }

    func addWords(_ words: [String]) {}
    func removeWords(_ words: [String]) {}
}
