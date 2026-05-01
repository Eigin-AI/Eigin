import Factory
import Foundation
import Observation

/// Manages connections to all configured MCP servers.
///
/// Lazily connects on the first chat send, caches connections for the session.
@Observable
final class MCPServerManager: @unchecked Sendable {
    private let keychainService: any KeychainService
    private let oauthService: any MCPOAuthService
    private var connections: [UUID: MCPServerConnection] = [:]
    private(set) var connectionErrors: [UUID: String] = [:]

    init(keychainService: any KeychainService, oauthService: any MCPOAuthService) {
        self.keychainService = keychainService
        self.oauthService = oauthService
    }

    /// Ensures all enabled servers are connected. Skips already-connected servers.
    func ensureConnected(servers: [MCPServer]) async {
        // Disconnect servers that were removed or disabled
        let enabledIDs = Set(servers.filter(\.isEnabled).map(\.id))
        for id in connections.keys where !enabledIDs.contains(id) {
            AppLogger.info("Disconnecting removed/disabled server \(public: id)", category: .mcp)
            await connections[id]?.disconnect()
            connections.removeValue(forKey: id)
            connectionErrors.removeValue(forKey: id)
        }

        // Connect new/enabled servers (already-connected servers are skipped;
        // MCPServerConnection handles reconnection transparently on failure).
        for server in servers where server.isEnabled {
            guard connections[server.id] == nil else { continue }
            guard let endpoint = URL(string: server.url) else {
                AppLogger.warning(
                    "Invalid URL for MCP server \(public: server.name)",
                    category: .mcp
                )
                connectionErrors[server.id] = "Invalid URL"
                continue
            }

            let authProvider: any MCPAuthProvider = switch server.authType {
            case .oauth:
                OAuthAuthProvider(oauthService: oauthService, serverID: server.id)
            case .none:
                NoAuthProvider()
            }

            let connection = MCPServerConnection(
                serverName: server.name,
                endpoint: endpoint,
                authProvider: authProvider
            )

            do {
                try await connection.connect()
                connections[server.id] = connection
                connectionErrors.removeValue(forKey: server.id)

                // Cache discovered tool names
                let tools = await connection.tools()
                server.cachedToolNames = tools.map(\.name)
                server.updatedAt = .now
            } catch {
                AppLogger.error(
                    "Failed to connect MCP server \(public: server.name): \(private: error.localizedDescription)",
                    category: .mcp
                )
                connectionErrors[server.id] = error.localizedDescription
            }
        }
    }

    /// Connects to servers and returns tool proxies ready for use.
    /// Registers display names on ToolRegistry so both chat and live call stay in sync.
    func prepareTools(servers: [MCPServer]) async -> [any Tool] {
        await ensureConnected(servers: servers)
        let tools: [any Tool] = await toolProxies()
        await MainActor.run {
            for tool in tools {
                ToolRegistry.dynamicDisplayNames[tool.name] = tool.displayName
            }
        }
        return tools
    }

    /// Returns proxy tools for all connected servers.
    func toolProxies() async -> [MCPToolProxy] {
        var proxies: [MCPToolProxy] = []
        for (_, connection) in connections {
            let serverName = connection.serverName
            let tools = await connection.tools()
            for tool in tools {
                proxies.append(MCPToolProxy(
                    mcpTool: tool,
                    serverName: serverName,
                    connection: connection
                ))
            }
        }
        return proxies
    }

    /// Disconnects a specific server.
    func disconnect(serverID: UUID) async {
        await connections[serverID]?.disconnect()
        connections.removeValue(forKey: serverID)
        connectionErrors.removeValue(forKey: serverID)
    }

    /// Disconnects all servers.
    func disconnectAll() async {
        for (_, connection) in connections {
            await connection.disconnect()
        }
        connections.removeAll()
        connectionErrors.removeAll()
    }

    /// Whether a specific server is currently connected.
    func isConnected(serverID: UUID) -> Bool {
        connections[serverID] != nil
    }
}
