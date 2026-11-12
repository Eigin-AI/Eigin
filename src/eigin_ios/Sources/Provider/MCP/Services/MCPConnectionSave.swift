import Foundation
import SwiftData

/// Completes verified setup by saving the connection and transferring its temporary OAuth tokens.
@MainActor
enum MCPConnectionSave {
    struct VerifiedConnection {
        let name: String
        let url: String
        let authType: MCPAuthType
        let toolNames: [String]
        let instructions: String?
        let oauth: OAuthConfiguration?
        let temporaryID: UUID
    }

    /// Reuses preset associations while leaving manually entered addresses independent.
    @discardableResult
    static func save(
        _ verified: VerifiedConnection, preset: MCPPreset?, context: ModelContext,
        keychain: any KeychainService
    ) throws -> MCPServer {
        let existing = try preset.flatMap { preset in
            try preset.server(in: context.fetch(FetchDescriptor<MCPServer>()))
        }
        defer { discard(temporaryID: verified.temporaryID, keychain: keychain) }
        // Another setup flow may have completed while authentication was open.
        if let existing, existing.isEnabled { return existing }
        let server = existing ?? MCPServer(
            name: verified.name,
            url: verified.url,
            authType: verified.authType
        )
        server.presetID = preset?.id
        server.isEnabled = true
        server.authType = verified.authType
        server.url = verified.url
        server.cachedToolNames = verified.toolNames
        server.serverInstructions = verified.instructions
        server.updatedAt = .now
        if let config = verified.oauth {
            server.oauthClientID = config.clientID
            server.oauthAuthURL = config.authorizationEndpoint.absoluteString
            server.oauthTokenURL = config.tokenEndpoint.absoluteString
            server.oauthScopes = config.scopes?.joined(separator: " ")
        }
        if existing == nil { context.insert(server) }
        if verified.authType == .oauth {
            for suffix in MCPServer.keychainSuffixes {
                if let value = keychain.read(key: keychain.mcpKey(
                    for: verified.temporaryID,
                    suffix: suffix
                )) {
                    keychain.save(
                        key: keychain.mcpKey(for: server.id, suffix: suffix),
                        value: value
                    )
                }
            }
        }
        if let preset { DeclinedCapabilities().clearPreset(preset.id) }
        return server
    }

    /// Removes credentials belonging to an abandoned or completed setup attempt.
    static func discard(temporaryID: UUID, keychain: any KeychainService) {
        for suffix in MCPServer.keychainSuffixes {
            keychain.delete(key: keychain.mcpKey(for: temporaryID, suffix: suffix))
        }
    }
}
