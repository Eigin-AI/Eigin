import EiginSDK
import Testing

@Suite("Model catalog bindings")
struct ModelCatalogTests {
    @Test func recordsOptionalsAndIntegerConversionsCrossBindings() throws {
        typealias Catalog = EiginSDK.ModelCatalog
        let entry = try #require(Catalog.entries.first)
        let match = try #require(Catalog.lookup(entry.pattern))
        #expect(match.entry == entry)
        #expect(match.versionTag == nil)
        #expect(Catalog.lookup("unknown-test-model") == nil)
        #expect(Catalog.preferenceRank(entry.pattern) == Catalog.preferenceRanking.firstIndex(of: entry.pattern))
        #expect(Catalog.boundedReasoningEffort(.max, model: entry.pattern, baseURL: "https://unverified.example") == .max)
        #expect(Catalog.boundedReasoningEffort(nil, model: entry.pattern, baseURL: "https://unverified.example") == nil)
        #expect(Catalog.imageInputBudget(width: .max, height: .max, model: entry.pattern) == .max)
    }
}
