@testable import Eigin
import Testing

@Suite("Integration recommendations")
struct IntegrationRecommendationsTests {
    private var all: [IntegrationCatalogEntry] {
        BundledIntegrationType.all.map(IntegrationCatalogEntry.integration)
            + MCPPreset.all.map(IntegrationCatalogEntry.mcpPreset)
    }

    @Test func prioritizesLocalToolsAndCommonServicesAcrossCategories() {
        let expected: [IntegrationCatalogEntry] = [
            .integration(BundledIntegrationType.appleCalendar),
            .integration(BundledIntegrationType.appleReminders),
            .integration(BundledIntegrationType.google),
            .integration(BundledIntegrationType.aula),
        ]
        #expect(IntegrationCatalogEntry.recommendations(from: all).map(\.id) == expected.map(\.id))
    }

    @Test func fillsVacanciesWithLowerRankedServices() {
        let connected = Set([
            BundledIntegrationType.appleCalendar, BundledIntegrationType.appleReminders,
            BundledIntegrationType.google, BundledIntegrationType.aula,
        ].map { IntegrationCatalogEntry.integration($0).id })
        let remaining = all.filter { !connected.contains($0.id) }
        let expected: [IntegrationCatalogEntry] = [
            .integration(BundledIntegrationType.microsoft),
            .integration(BundledIntegrationType.imap),
            .mcpPreset(.dinero),
            .mcpPreset(.pleo),
        ]
        #expect(IntegrationCatalogEntry.recommendations(from: remaining).map(\.id) == expected
            .map(\.id))
    }

    @Test func capsResultsAndOnlyReturnsAvailableEntries() {
        let available = Array(all.dropFirst())
        let results = IntegrationCatalogEntry.recommendations(from: available)
        #expect(results.count == 4)
        #expect(Set(results.map(\.id)).isSubset(of: Set(available.map(\.id))))
        #expect(Set(results.map(\.id)).count == results.count)
    }

    @Test func returnsAllAvailableEntriesWhenFewerThanFourRemain() {
        let available: [IntegrationCatalogEntry] = [.mcpPreset(.pleo), .mcpPreset(.notion)]
        let results = IntegrationCatalogEntry.recommendations(from: available)
        #expect(results.count == 2)
        #expect(Set(results.map(\.id)) == Set(available.map(\.id)))
    }

    @Test func returnsNoRecommendationsWhenNothingIsAvailable() {
        #expect(IntegrationCatalogEntry.recommendations(from: []).isEmpty)
    }

    @Test func filtersEnabledConnectionsBeforeCappingAndKeepsDisabledConnections() {
        let types = [
            BundledIntegrationType.appleCalendar,
            BundledIntegrationType.appleReminders,
            BundledIntegrationType.google,
            BundledIntegrationType.aula,
            BundledIntegrationType.microsoft,
            BundledIntegrationType.imap,
        ]
        let integrations = types.map {
            Integration(typeID: $0.id, accountLabel: "Test", grantedCapabilities: [])
        }
        let dinero = MCPServer(name: "Dinero", url: MCPPreset.dinero.endpoint.absoluteString)
        dinero.presetID = "dinero"
        let pleo = MCPServer(
            name: "Pleo",
            url: MCPPreset.pleo.endpoint.absoluteString,
            isEnabled: false
        )
        pleo.presetID = "pleo"
        let manual = MCPServer(name: "Pleo", url: MCPPreset.pleo.endpoint.absoluteString)
        let servers = [dinero, pleo, manual]
        let expected: [IntegrationCatalogEntry] = [
            .mcpPreset(.pleo), .mcpPreset(.notion), .mcpPreset(.basecamp),
            .integration(BundledIntegrationType.appleHealth),
        ]
        #expect(IntegrationCatalogEntry.listed(integrations: integrations, servers: servers)
            .map(\.id) == expected.map(\.id))
        integrations[0].isEnabled = false
        #expect(IntegrationCatalogEntry.listed(integrations: integrations, servers: servers)
            .first?.id == IntegrationCatalogEntry.integration(BundledIntegrationType.appleCalendar)
            .id)
    }

    @Test func searchAndCategoriesRetainLowerRankedServices() {
        #expect(IntegrationCatalogEntry.listed(integrations: [], servers: [], search: "Pleo")
            .map(\.id)
            == [IntegrationCatalogEntry.mcpPreset(.pleo).id])
        let finance = IntegrationCatalogEntry.listed(
            integrations: [],
            servers: [],
            category: .finance
        )
        #expect(Set(finance.map(\.id)) == Set([
            IntegrationCatalogEntry.mcpPreset(.dinero).id,
            IntegrationCatalogEntry.mcpPreset(.pleo).id,
        ]))
        #expect(IntegrationCatalogEntry.listed(
            integrations: [],
            servers: [],
            category: .email,
            search: "Pleo"
        ).isEmpty)
    }
}
