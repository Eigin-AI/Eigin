@testable import Eigin
import Foundation
import Testing

@Suite("IntegrationSearch")
struct IntegrationSearchTests {
    @Test func emptyQueryMatchesNothing() {
        #expect(IntegrationSearch.matching("").isEmpty)
        #expect(IntegrationSearch.matching("   ").isEmpty)
    }

    @Test func matchesByDisplayName() {
        let results = IntegrationSearch.matching("goo")
        #expect(results.map(\.id) == ["google"])
    }

    @Test func matchesByDescriptionCaseInsensitively() {
        let results = IntegrationSearch.matching("READ AND SEND EMAIL")
        #expect(Set(results.map(\.id)) == Set(["google", "microsoft"]))
    }

    @Test func matchesByCategoryDisplayName() {
        let results = IntegrationSearch.matching("family")
        #expect(results.map(\.id) == ["aula"])
    }

    @Test func noMatchReturnsEmpty() {
        #expect(IntegrationSearch.matching("nonexistent-service").isEmpty)
    }

    /// Add Integration narrows the scope to the active category chip, so a
    /// query that matches elsewhere must not leak back in.
    @Test func scopedSearchOnlyMatchesWithinTheGivenTypes() {
        let emailScope = IntegrationCategory.email.integrationTypes
        #expect(IntegrationSearch.matching("google", in: emailScope).map(\.id) == ["google"])
        #expect(IntegrationSearch.matching("aula", in: emailScope).isEmpty)
    }
}
