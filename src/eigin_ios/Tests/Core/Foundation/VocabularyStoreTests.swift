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
        let words = store.userWords()
        #expect(words.contains("Hello"))
        #expect(words.contains("World"))
    }

    @Test func removeWords() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["Alpha", "Beta", "Gamma"])
        store.removeWords(["Beta"])
        let words = store.userWords()
        #expect(words.contains("Alpha"))
        #expect(!words.contains("Beta"))
        #expect(words.contains("Gamma"))
    }

    @Test func deduplication() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["Foo", "Foo", "Bar"])
        let words = store.userWords()
        #expect(words.count(where: { $0 == "Foo" }) == 1)
        #expect(words.contains("Bar"))

        // Adding again doesn't duplicate
        store.addWords(["Foo"])
        #expect(store.userWords().count(where: { $0 == "Foo" }) == 1)
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

        #expect(store.userWords().isEmpty)
    }

    @Test func trimWhitespace() {
        let store = makeStore()
        defer { cleanup() }

        store.addWords(["  Padded  ", ""])
        let words = store.userWords()
        #expect(words.contains("Padded"))
        #expect(!words.contains(""))
        #expect(!words.contains("  Padded  "))
    }
}
