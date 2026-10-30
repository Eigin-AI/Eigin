import Foundation
import MCP

/// Manages a single MCP server connection via the MCP Swift SDK.
///
/// Each instance owns one ``MCP.Client`` and its transport. The actor
/// isolation ensures thread-safe access to the client state.
///
/// Uses non-streaming (stateless) HTTP transport so each request is
/// independent — no persistent SSE connection. This works well with
/// servers that may shut down between requests (e.g. Cloud Run).
/// On any failure the connection is torn down and re-established
/// with a fresh token before retrying.
actor MCPServerConnection {
    nonisolated let serverName: String
    private let httpConfiguration: URLSessionConfiguration
    private let endpoint: URL
    private let authProvider: any MCPAuthProvider

    private var client: Client?
    private var discoveredTools: [MCP.Tool] = []
    private var discoveredInstructions: String?
    private let tokenCache = TokenCache()

    enum ConnectionError: Error, LocalizedError {
        case invalidURL
        case notConnected
        case connectionFailed(String)
        case authExpired

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid server URL"
            case .notConnected: "Not connected to MCP server"
            case .connectionFailed(let reason): "Connection failed: \(reason)"
            case .authExpired: "Session expired. Re-authorize in Settings → MCP Servers."
            }
        }
    }

    init(
        serverName: String, endpoint: URL, authProvider: any MCPAuthProvider,
        httpConfiguration: URLSessionConfiguration = .default
    ) {
        self.httpConfiguration = httpConfiguration
        self.serverName = serverName
        self.endpoint = endpoint
        self.authProvider = authProvider
    }

    /// Connects to the MCP server, initialises the protocol, and discovers tools.
    func connect() async throws {
        let mcpClient = Client(name: "Eigin", version: "1.0.0")

        let token = try await authProvider.currentToken()
        tokenCache.current = token

        let cache = tokenCache
        let transport = HTTPClientTransport(
            endpoint: endpoint,
            configuration: httpConfiguration,
            streaming: false,
            requestModifier: { request in
                var req = request
                if let t = cache.current {
                    req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                }
                return req
            }
        )

        let initializeResult: Initialize.Result
        do {
            initializeResult = try await mcpClient.connect(transport: transport)
        } catch {
            throw ConnectionError.connectionFailed(error.localizedDescription)
        }

        client = mcpClient
        discoveredInstructions = initializeResult.instructions

        // Discover available tools
        let (tools, _) = try await mcpClient.listTools()
        discoveredTools = tools
        AppLogger.info(
            "Connected to \(public: serverName), discovered \(public: tools.count) tools",
            category: .mcp
        )
    }

    /// Tears down the current connection and re-establishes a fresh one.
    /// Fetches the current token (refreshed automatically if expired).
    /// Used when a tool call fails (server restarted, token expired, etc.).
    private func reconnect() async throws {
        AppLogger.info("Reconnecting to \(public: serverName)", category: .mcp)
        client = nil

        let token = try await authProvider.currentToken()
        guard let token else { throw ConnectionError.authExpired }
        tokenCache.current = token

        let cache = tokenCache
        let transport = HTTPClientTransport(
            endpoint: endpoint,
            configuration: httpConfiguration,
            streaming: false,
            requestModifier: { request in
                var req = request
                if let t = cache.current {
                    req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                }
                return req
            }
        )

        let mcpClient = Client(name: "Eigin", version: "1.0.0")

        let initializeResult: Initialize.Result
        do {
            initializeResult = try await mcpClient.connect(transport: transport)
        } catch {
            throw ConnectionError.connectionFailed(error.localizedDescription)
        }

        client = mcpClient
        discoveredInstructions = initializeResult.instructions

        let (tools, _) = try await mcpClient.listTools()
        discoveredTools = tools
    }

    /// Disconnects from the MCP server.
    func disconnect() async {
        AppLogger.info("Disconnected from \(public: serverName)", category: .mcp)
        client = nil
        discoveredTools = []
        discoveredInstructions = nil
    }

    /// Returns the tools discovered during connection.
    func tools() -> [MCP.Tool] {
        discoveredTools
    }

    /// Returns the server's self-reported `instructions` from `initialize`, if any.
    func instructions() -> String? {
        discoveredInstructions
    }

    /// Calls a tool on the remote MCP server.
    ///
    /// If the call fails for any reason (auth expired, server restarted, network
    /// error), tears down the connection, gets a fresh token, reconnects, and
    /// retries once. This handles Cloud Run cold starts, token expiry, and
    /// transient failures transparently.
    func callTool(
        name: String,
        arguments: [String: Value]?
    ) async throws -> (content: [MCP.Tool.Content], isError: Bool?) {
        guard client != nil else { throw ConnectionError.notConnected }

        do {
            return try await client!.callTool(name: name, arguments: arguments)
        } catch {
            AppLogger.warning(
                "Tool call \(public: name) failed: \(private: error.localizedDescription). Reconnecting.",
                category: .mcp
            )
            do {
                try await reconnect()
                return try await client!.callTool(name: name, arguments: arguments)
            } catch {
                AppLogger.error(
                    "Retry after reconnect failed: \(private: error.localizedDescription)",
                    category: .mcp
                )
                throw error
            }
        }
    }
}
