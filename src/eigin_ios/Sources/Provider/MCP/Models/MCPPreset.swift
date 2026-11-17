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
    let searchDescriptor: String
    /// Preferred OAuth callback; nil uses the app callback.
    let oauthCallback: MCPOAuthCallback?

    var skillID: String {
        "mcp_preset__\(id)"
    }

    private let localizedDescription: @Sendable () -> String
    private let localizedConnectionDescription: @Sendable () -> String

    var description: String {
        localizedDescription()
    }

    var connectionDescription: String {
        localizedConnectionDescription()
    }

    static let dinero = MCPPreset(
        id: "dinero", displayName: "Dinero", endpoint: URL(string: "https://mcp.dinero.dk")!,
        category: .finance, brandImage: Iconography.Service.dinero,
        instructions: Prompt.Skills.Dinero.instruction,
        searchDescriptor: "Dinero Danish accounting: invoices, bookkeeping, purchases, payments, financial reports and account setup.",
        oauthCallback: nil,
        localizedDescription: { Localized.Integrations.Dinero.description },
        localizedConnectionDescription: { Localized.Integrations.Dinero.connectionDescription }
    )
    static let basecamp = MCPPreset(
        id: "basecamp", displayName: "Basecamp",
        endpoint: URL(string: "https://mcp.basecamp.com/mcp")!,
        category: .work, brandImage: Iconography.Service.basecamp,
        instructions: Prompt.Skills.Basecamp.instruction,
        searchDescriptor: "Basecamp project management: projects, to-dos, tasks, message boards, discussions, schedules, documents and team collaboration.",
        oauthCallback: .httpsRedirect,
        localizedDescription: { Localized.Integrations.Basecamp.description },
        localizedConnectionDescription: { Localized.Integrations.Basecamp.connectionDescription }
    )
    static let notion = MCPPreset(
        id: "notion", displayName: "Notion",
        endpoint: URL(string: "https://mcp.notion.com/mcp")!,
        category: .work, brandImage: Iconography.Service.notion,
        instructions: Prompt.Skills.Notion.instruction,
        searchDescriptor: "Notion workspace knowledge: search, read, create and update notes, pages, documents, databases and wikis.",
        oauthCallback: .app,
        localizedDescription: { Localized.Integrations.Notion.description },
        localizedConnectionDescription: { Localized.Integrations.Notion.connectionDescription }
    )
    static let pleo = MCPPreset(
        id: "pleo", displayName: "Pleo", endpoint: URL(string: "https://mcp.pleo.io/mcp")!,
        category: .finance, brandImage: Iconography.Service.pleo,
        instructions: Prompt.Skills.Pleo.instruction,
        searchDescriptor: "Pleo Danish spend management: expenses, receipts, spending insights and company spending.",
        oauthCallback: nil,
        localizedDescription: { Localized.Integrations.Pleo.description },
        localizedConnectionDescription: { Localized.Integrations.Pleo.connectionDescription }
    )
    static let all = [dinero, basecamp, notion, pleo]

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
