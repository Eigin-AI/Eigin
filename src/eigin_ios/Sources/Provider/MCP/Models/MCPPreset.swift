import Foundation
import SwiftUI

/// A bundled connection address and high-level guidance for a discoverable MCP service.
struct MCPPreset: Identifiable, Sendable {
    let id: String
    let displayName: String
    let endpoint: URL
    let category: IntegrationCategory
    let brandImage: Image
    let instructions: String

    var skillID: String {
        "mcp_preset__\(id)"
    }

    var description: String {
        Localized.Integrations.Dinero.description
    }

    var connectionDescription: String {
        Localized.Integrations.Dinero.connectionDescription
    }

    static let dinero = MCPPreset(
        id: "dinero", displayName: "Dinero", endpoint: URL(string: "https://mcp.dinero.dk")!,
        category: .finance, brandImage: Iconography.Service.dinero,
        instructions: Prompt.Skills.Dinero.instruction
    )
    static let all = [dinero]

    /// Looks up a bundled preset by its stable skill identifier.
    static func forSkillID(_ skillID: String) -> MCPPreset? {
        all.first { $0.skillID == skillID }
    }

    /// Finds only explicitly associated connections; manually added addresses stay independent.
    func server(in servers: [MCPServer]) -> MCPServer? {
        servers.filter { $0.presetID == id }.sorted { $0.createdAt < $1.createdAt }.first
    }
}

extension MCPServer {
    /// Separate tool namespace for preset connections, even alongside an identically named manual
    /// server.
    var toolNamespace: String {
        presetID == nil ? name : "p\(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }
}
