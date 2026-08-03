@testable import Eigin
import Foundation
import Testing

/// Covers category membership, which each `IntegrationType` declares through
/// its own `category`.
@Suite("IntegrationCategory")
struct IntegrationCategoryTests {
    @Test func emailCategoryGroupsAllEmailProviders() {
        let types = IntegrationCategory.email.integrationTypes.map(\.id)
        #expect(Set(types) == Set(["google", "microsoft", "imap"]))
    }

    @Test func familyAndSchoolCategoryGroupsAula() {
        let types = IntegrationCategory.familyAndSchool.integrationTypes.map(\.id)
        #expect(types == ["aula"])
    }

    @Test func placeholderCategoriesHaveNoProviders() {
        #expect(IntegrationCategory.health.integrationTypes.isEmpty)
        #expect(IntegrationCategory.music.integrationTypes.isEmpty)
    }

    @Test func isAvailableReflectsWhetherAProviderExists() {
        #expect(IntegrationCategory.email.isAvailable)
        #expect(IntegrationCategory.familyAndSchool.isAvailable)
        #expect(!IntegrationCategory.health.isAvailable)
        #expect(!IntegrationCategory.music.isAvailable)
    }

    @Test func browseOrderPutsAvailableCategoriesFirst() {
        let order = IntegrationCategory.browseOrder
        let availableCount = order.prefix(while: \.isAvailable).count
        #expect(availableCount == order.filter(\.isAvailable).count)
    }

    @Test func categoryForCapabilityResolvesToTheOwningType() {
        #expect(IntegrationCategory.category(for: .email) == .email)
        #expect(IntegrationCategory.category(for: .aula) == .familyAndSchool)
    }
}
