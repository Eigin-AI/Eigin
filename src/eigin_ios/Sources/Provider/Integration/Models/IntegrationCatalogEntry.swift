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
