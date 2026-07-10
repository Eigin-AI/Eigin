import Foundation
import SwiftData

extension SchemaV6 {
    @Model
    final class MCPServer {
        var id: UUID
        var name: String
        var url: String
        var authType: MCPAuthType
        var oauthClientID: String?
        var oauthAuthURL: String?
        var oauthTokenURL: String?
        var oauthScopes: String?
        var isEnabled: Bool
        var cachedToolNames: [String] = []
        /// The server's self-reported `instructions` string from MCP's
        /// `initialize` response, cached on connect so the activation catalog
        /// can render name + instructions + tools without a live connection.
        var serverInstructions: String?
        var createdAt: Date
        var updatedAt: Date

        /// Keychain storage suffixes for MCP server credentials.
        static let keychainSuffixes = [
            "apikey", "access_token", "refresh_token", "token_expiry",
            "token_endpoint", "client_id", "client_secret", "resource",
        ]

        init(
            name: String,
            url: String,
            authType: MCPAuthType = .none,
            isEnabled: Bool = true
        ) {
            id = UUID()
            self.name = name
            self.url = url
            self.authType = authType
            self.isEnabled = isEnabled
            createdAt = .now
            updatedAt = .now
        }
    }
}
