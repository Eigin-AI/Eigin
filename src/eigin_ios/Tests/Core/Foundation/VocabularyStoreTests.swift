@testable import Eigin
import Foundation
import Testing

@Suite("VocabularyStore")
struct VocabularyStoreTests {
    private let suiteName = "VocabularyStoreTests.\(UUID().uuidString)"

    private func makeStore() -> DefaultVocabularyStore {
        DefaultVocabularyStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    private func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test func addAndListWords() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["Hello", "World"])
        let words = store.userEntries().map(\.word)
        #expect(words.contains("Hello"))
        #expect(words.contains("World"))
    }

    @Test func removeWords() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["Alpha", "Beta", "Gamma"])
        store.removeWords(["Beta"])
        let words = store.userEntries().map(\.word)
        #expect(words.contains("Alpha"))
        #expect(!words.contains("Beta"))
        #expect(words.contains("Gamma"))
    }

    @Test func deduplication() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["Foo", "Foo", "Bar"])
        let words = store.userEntries().map(\.word)
        #expect(words.count(where: { $0 == "Foo" }) == 1)
        #expect(words.contains("Bar"))

        // Adding again doesn't duplicate
        store.addWords(["Foo"])
        #expect(store.userEntries().map(\.word).count(where: { $0 == "Foo" }) == 1)
    }

    @Test func allWordsCombinesBuiltInAgentAndUser() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["CustomWord"])
        let all = store.allWords(agentName: "Atlas")

        #expect(all.contains("Eigin"))
        #expect(all.contains("Atlas"))
        #expect(all.contains("CustomWord"))
    }

    @Test func allWordsDeduplicates() {
        let store = makeStore()
        defer { cleanup() }

        // "Eigin" is built-in, adding it as user word should not duplicate
        store.addWords(["Eigin"])
        let all = store.allWords(agentName: "TestAgent")
        #expect(all.count(where: { $0 == "Eigin" }) == 1)
    }

    @Test func allWordsDeduplicatesAgentName() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["Atlas"])
        let all = store.allWords(agentName: "Atlas")
        #expect(all.count(where: { $0 == "Atlas" }) == 1)
    }

    @Test func emptyStoreReturnsEmpty() {
        let store = makeStore()
        defer { cleanup() }

        #expect(store.userEntries().map(\.word).isEmpty)
    }

    @Test func trimWhitespace() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["  Padded  ", ""])
        let words = store.userEntries().map(\.word)
        #expect(words.contains("Padded"))
        #expect(!words.contains(""))
        #expect(!words.contains("  Padded  "))
    }

    @Test func addAliasCreatesAndAttaches() {
        let store = makeStore()
        defer { cleanup() }

        store.addAlias("tackle", for: "Therkel")
        let entries = store.userEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.word == "Therkel")
        #expect(entries.first?.aliases == ["tackle"])
    }

    @Test func addAliasAppendsToExistingEntry() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["Therkel"])
        store.addAlias("tackle", for: "Therkel")
        store.addAlias("taggle", for: "therkel") // case-insensitive word match
        store.addAlias("tackle", for: "Therkel") // duplicate ignored

        let entries = store.userEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.aliases == ["tackle", "taggle"])
    }

    @Test func addAliasOnBuiltInMergesIntoBuiltInEntry() {
        let store = makeStore()
        defer { cleanup() }

        // "Eigin" is built-in; a user alias on it must merge into the same
        // entry rather than duplicate the word.
        store.addAlias("eigenk", for: "Eigin")

        let entries = store.entries(agentName: "Atlas")
        #expect(entries.count(where: { $0.word == "Eigin" }) == 1)
        let aliases = entries.first(where: { $0.word == "Eigin" })?.aliases
        #expect(aliases?.contains("eigen") == true)
        #expect(aliases?.contains("eigenk") == true)
        #expect(aliases?.contains("iGen") == true)
    }

    @Test func legacyStringListMigratesToEntries() throws {
        let store = makeStore()
        defer { cleanup() }

        // Write data in the old flat [String] format.
        let legacy = try JSONEncoder().encode(["Therkel", "Infercom"])
        UserDefaults(suiteName: suiteName)?.set(legacy, forKey: "vocabulary")

        let entries = store.userEntries()
        #expect(entries.map(\.word).sorted() == ["Infercom", "Therkel"])
        #expect(entries.allSatisfy { $0.aliases.isEmpty })

        // Re-reading finds the migrated entry format (encoded, not re-migrated).
        #expect(store.userEntries().map(\.word).sorted() == ["Infercom", "Therkel"])
    }
}
