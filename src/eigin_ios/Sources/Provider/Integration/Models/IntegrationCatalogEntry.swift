import SwiftUI

/// Presentation metadata shared by built-in integrations and MCP presets.
enum IntegrationCatalogEntry: Identifiable {
    case integration(IntegrationType)
    case mcpPreset(MCPPreset)

    var target: ConnectTarget {
        switch self {
        case .integration(let type): .type(type)
        case .mcpPreset(let preset): .preset(preset)
        }
    }

    var id: String {
        target.id
    }

    var displayName: String {
        switch self {
        case .integration(let type): type.displayName
        case .mcpPreset(let preset): preset.displayName
        }
    }

    var description: String {
        switch self {
        case .integration(let type): type.description
        case .mcpPreset(let preset): preset.description
        }
    }

    var category: IntegrationCategory {
        switch self {
        case .integration(let type): type.category
        case .mcpPreset(let preset): preset.category
        }
    }

    var image: Image? {
        switch self {
        case .integration(let type): type.brandImage
        case .mcpPreset(let preset): preset.brandImage
        }
    }

    /// All services in recommendation order, across categories.
    static var recommended: [Self] {
        [
            .integration(BundledIntegrationType.appleCalendar),
            .integration(BundledIntegrationType.appleReminders),
            .integration(BundledIntegrationType.google),
            .integration(BundledIntegrationType.aula),
            .integration(BundledIntegrationType.microsoft),
            .integration(BundledIntegrationType.imap),
            .mcpPreset(.dinero),
            .mcpPreset(.pleo),
            .mcpPreset(.notion),
            .mcpPreset(.basecamp),
            .integration(BundledIntegrationType.appleHealth),
            .integration(BundledIntegrationType.location),
        ]
    }

    /// Suggests up to four services after connected entries have been excluded.
    static func recommendations(from availableEntries: [Self]) -> [Self] {
        let availableIDs = Set(availableEntries.map(\.id))
        return Array(recommended.filter { availableIDs.contains($0.id) }.prefix(4))
    }

    /// Selects unconnected services for recommendations, category browsing, or search.
    static func listed(
        integrations: [Integration], servers: [MCPServer],
        category: IntegrationCategory? = nil, search: String = ""
    ) -> [Self] {
        let connected = Set(integrations.filter(\.isEnabled).map(\.typeID))
        var entries = BundledIntegrationType.all.filter { !connected.contains($0.id) }
            .map(Self.integration)
        entries += MCPPreset.all.filter { $0.server(in: servers)?.isEnabled != true }
            .map(Self.mcpPreset)
        if category == nil && search.isEmpty {
            return recommendations(from: entries)
        }
        if let category { entries = entries.filter { $0.category == category } }
        return search.isEmpty ? entries : matching(search, in: entries)
    }

    /// Filters catalog entries without changing the underlying connection mechanisms.
    static func matching(_ query: String, in entries: [Self]) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return entries.filter {
            [$0.displayName, $0.description, $0.category.displayName]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}
