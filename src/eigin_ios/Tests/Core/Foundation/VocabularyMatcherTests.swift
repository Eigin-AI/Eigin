@testable import Eigin
import Foundation
import Testing

@Suite("VocabularyMatcher")
struct VocabularyMatcherTests {
    private func entry(_ word: String, aliases: [String] = []) -> VocabularyEntry {
        VocabularyEntry(word: word, aliases: aliases)
    }

    private func matches(
        _ transcript: String, _ vocabulary: [VocabularyEntry]
    ) -> [VocabularyMatcher.Match] {
        VocabularyMatcher.matches(transcript: transcript, vocabulary: vocabulary)
    }

    // MARK: - Alias pass

    @Test func aliasHitMatchesLiterally() {
        let results = matches(
            "take tackle to the dry cleaner",
            [entry("Therkel", aliases: ["tackle"])]
        )
        #expect(results == [
            VocabularyMatcher.Match(said: "tackle", suggestion: "Therkel", isKnownAlias: true),
        ])
    }

    @Test func aliasMatchIsCaseInsensitive() {
        let results = matches(
            "hey Eigen, let's go", [entry("Eigin", aliases: ["eigen"])]
        )
        #expect(results.first?.isKnownAlias == true)
        #expect(results.first?.suggestion == "Eigin")
    }

    // MARK: - Edit distance pass

    @Test func closeMissMatchesByDistance() {
        let results = matches("tell eigen about it", [entry("Eigin")])
        #expect(results == [
            VocabularyMatcher.Match(said: "eigen", suggestion: "Eigin", isKnownAlias: false),
        ])
    }

    @Test func distanceMatchesLongerWords() {
        let results = matches("compare the intercom", [entry("Infercom")])
        #expect(results.first?.suggestion == "Infercom")
        #expect(results.first?.isKnownAlias == false)
    }

    @Test func farMissDoesNotMatch() {
        // "blender" is nowhere near "Therkel" and not an alias.
        #expect(matches("put it in the blender", [entry("Therkel")]).isEmpty)
    }

    @Test func exactHitIsSkipped() {
        #expect(matches("hello Therkel, lovely day", [entry("Therkel")]).isEmpty)
    }

    @Test func exactHitCaseAndDiacriticInsensitive() {
        #expect(matches("hello therkel", [entry("Therkel")]).isEmpty)
        #expect(matches("hello über", [entry("Uber")]).isEmpty)
    }

    @Test func shortWordsNeverFuzzyMatch() {
        // 3-letter word: any single edit is below the fuzzy threshold.
        #expect(matches("the cat sat", [entry("cut")]).isEmpty)
    }

    // MARK: - Multi-word entries

    @Test func spacedOutTokensMatchCompoundEntry() {
        let results = matches("call a k q a tomorrow", [entry("AKQA")])
        #expect(results.first?.suggestion == "AKQA")
        #expect(results.first?.said == "a k q a")
    }

    @Test func ordinaryProseJoinsDoNotMatch() {
        // Multi-token windows only fire on exact spelled-out joins — not on
        // near-miss joins of common words.
        #expect(matches("tell me a tale", [entry("Atlas")]).isEmpty)
        #expect(matches("at last we go", [entry("Atlas")]).isEmpty)
        #expect(matches("the ear of corn", [entry("Eigin")]).isEmpty)
    }

    @Test func misspelledWordWithinProseStillMatches() {
        let results = matches("eigen and atlas say hi", [entry("Eigin"), entry("Atlass")])
        #expect(Set(results.map(\.suggestion)) == Set(["Eigin", "Atlass"]))
    }

    // MARK: - Selection and capping

    @Test func aliasHitOutranksDistanceHit() {
        let results = matches(
            "taggle the tackle", [entry("Therkel", aliases: ["taggle"])]
        )
        #expect(results.count == 1)
        #expect(results.first?.said == "taggle")
        #expect(results.first?.isKnownAlias == true)
    }

    @Test func multipleEntriesProduceMultipleMatches() {
        let results = matches("infercon want eigen", [entry("Infercom"), entry("Eigin")])
        #expect(Set(results.map(\.suggestion)) == Set(["Infercom", "Eigin"]))
    }

    @Test func matchesAreCapped() {
        // Five entries, all one edit away from "bananb" ... use a 10-letter
        // stem so distance 2 is allowed.
        let vocab = (0 ..< 5).map { entry("mistransc\($0)a") }
        let results = matches("mistransct", vocab)
        #expect(results.count == VocabularyMatcher.matchLimit)
    }

    @Test func oneEntryProducesOneBestMatch() {
        let results = matches("eigln and eigon and eigen", [entry("Eigin")])
        #expect(results.count == 1)
    }

    @Test func emptyTranscriptReturnsEmpty() {
        #expect(matches("", [entry("Eigin")]).isEmpty)
    }

    @Test func emptyVocabularyReturnsEmpty() {
        #expect(matches("something", []).isEmpty)
    }
}
