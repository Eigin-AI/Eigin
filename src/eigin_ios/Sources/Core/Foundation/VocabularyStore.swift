import Factory
import Foundation

/// A vocabulary word the speech-recognition and mistranscription-hint pipeline
/// should know about, plus known mistranscriptions of it.
///
/// Aliases are words the transcriber is known to produce instead of `word`
/// (e.g. "eigen" for "Eigin") — learned by the agent over time via
/// ``ManageVocabularyTool``.
struct VocabularyEntry: Codable, Equatable, Sendable {
    let word: String
    var aliases: [String]

    init(word: String, aliases: [String] = []) {
        self.word = word
        self.aliases = aliases
    }
}

/// Manages the vocabulary that feeds speech recognition contextual strings and
/// the per-turn mistranscription hints.
protocol VocabularyStore: Sendable {
    /// Returns built-in entries + agent name + user entries, deduplicated by
    /// word (aliases merged across duplicates).
    func entries(agentName: String) -> [VocabularyEntry]
    /// Flattened word list — built-ins + agent name + user words.
    func allWords(agentName: String) -> [String]
    /// Just user-managed entries.
    func userEntries() -> [VocabularyEntry]
    func addWords(_ words: [String])
    /// Records `alias` as a known mistranscription of `word`. Creates the word
    /// as a user entry if it doesn't exist yet.
    func addAlias(_ alias: String, for word: String)
    func removeWords(_ words: [String])
}

final class DefaultVocabularyStore: VocabularyStore {
    static let builtInEntries = [
        VocabularyEntry(word: "Eigin", aliases: ["eigen", "iGen"]),
    ]

    private static let defaultsKey = "vocabulary"
    private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func entries(agentName: String) -> [VocabularyEntry] {
        var seen = [String: Int]() // normalized word -> index into result
        var result = [VocabularyEntry]()
        for entry in Self.builtInEntries + [VocabularyEntry(word: agentName)] + userEntries() {
            let word = normalized(entry.word)
            guard !word.isEmpty else { continue }
            if let index = seen[word] {
                // Same word from built-ins and user entries — merge aliases.
                for alias in entry.aliases where !result[index].aliases.contains(alias) {
                    result[index].aliases.append(alias)
                }
            } else {
                seen[word] = result.count
                result.append(VocabularyEntry(
                    word: entry.word.trimmingCharacters(in: .whitespaces),
                    aliases: entry.aliases
                ))
            }
        }
        return result
    }

    func allWords(agentName: String) -> [String] {
        entries(agentName: agentName).map(\.word)
    }

    func userEntries() -> [VocabularyEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
        if let entries = try? JSONDecoder().decode([VocabularyEntry].self, from: data) {
            return entries
        }
        // Legacy format: a flat [String] list from before aliases existed.
        // Migrate to entries on first read.
        guard let words = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        let entries = words.map { VocabularyEntry(word: $0) }
        save(entries)
        return entries
    }

    func addWords(_ words: [String]) {
        var current = userEntries()
        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let index = current.firstIndex(where: {
                normalized($0.word) == normalized(trimmed)
            }) {
                continue
            }
            current.append(VocabularyEntry(word: trimmed))
        }
        save(current)
    }

    func addAlias(_ alias: String, for word: String) {
        let alias = alias.trimmingCharacters(in: .whitespaces)
        let word = word.trimmingCharacters(in: .whitespaces)
        // A self-alias would make the matcher hint exactly-transcribed words.
        guard !alias.isEmpty, !word.isEmpty, normalized(alias) != normalized(word) else { return }
        var current = userEntries()
        if let index = current.firstIndex(where: { normalized($0.word) == normalized(word) }) {
            guard !current[index].aliases.contains(where: { normalized($0) == normalized(alias) })
            else { return }
            current[index].aliases.append(alias)
        } else {
            current.append(VocabularyEntry(word: word, aliases: [alias]))
        }
        save(current)
    }

    func removeWords(_ words: [String]) {
        let toRemove = Set(words.map { normalized($0) })
        let filtered = userEntries().filter { !toRemove.contains(normalized($0.word)) }
        save(filtered)
    }

    private func normalized(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
    }

    private func save(_ entries: [VocabularyEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Preview stub — returns empty vocabulary.
struct PreviewVocabularyStore: VocabularyStore {
    func entries(agentName: String) -> [VocabularyEntry] {
        []
    }

    func allWords(agentName: String) -> [String] {
        []
    }

    func userEntries() -> [VocabularyEntry] {
        []
    }

    func addWords(_ words: [String]) {}
    func addAlias(_ alias: String, for word: String) {}
    func removeWords(_ words: [String]) {}
}
