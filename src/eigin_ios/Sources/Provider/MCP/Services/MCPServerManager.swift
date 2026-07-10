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

    /// Ensures the given servers are connected, skipping already-connected ones.
    /// Any tracked connection whose server isn't in `servers` (or has been
    /// disabled) is torn down. Callers pass the specific servers they need
    /// connected — e.g. those backing active skills in a chat, not every
    /// enabled server (see ``MCPServerSkill``, whose catalog needs no connection).
    func ensureConnected(servers: [MCPServer]) async {
        let targetIDs = Set(servers.filter(\.isEnabled).map(\.id))
        for id in connections.keys where !targetIDs.contains(id) {
            AppLogger.info("Disconnecting unneeded server \(public: id)", category: .mcp)
            await connections[id]?.disconnect()
            connections.removeValue(forKey: id)
            connectionErrors.removeValue(forKey: id)
        }

        for server in servers where server.isEnabled {
            guard connections[server.id] == nil else { continue }
            _ = await connect(server: server)
        }
    }

    /// Connects a single server, caching its discovered tool names and
    /// instructions on success. Used by ``ActivateSkillTool`` so activation
    /// can report success or an actionable error immediately.
    ///
    /// Returns `nil` on success (or if already connected), or an error
    /// description on failure.
    func connect(server: MCPServer) async -> String? {
        if connections[server.id] != nil { return nil }

        guard let endpoint = URL(string: server.url) else {
            AppLogger.warning(
                "Invalid URL for MCP server \(public: server.name)",
                category: .mcp
            )
            let message = "Invalid URL"
            connectionErrors[server.id] = message
            return message
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

            // Cache discovered tool names + instructions for the cache-driven catalog.
            let tools = await connection.tools()
            server.cachedToolNames = tools.map(\.name)
            server.serverInstructions = await connection.instructions()
            server.updatedAt = .now
            return nil
        } catch {
            AppLogger.error(
                "Failed to connect MCP server \(public: server.name): \(private: error.localizedDescription)",
                category: .mcp
            )
            let message = error.localizedDescription
            connectionErrors[server.id] = message
            return message
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
