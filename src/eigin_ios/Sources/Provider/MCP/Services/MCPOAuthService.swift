import Foundation

// MARK: - Protocol

protocol MCPOAuthService: Sendable {
    /// Probes server. Returns nil if open, OAuthConfiguration if 401.
    func discoverOAuth(for serverURL: URL) async throws -> OAuthConfiguration?

    /// Full PKCE flow: browser auth -> code exchange -> store tokens in Keychain.
    func authorize(config: OAuthConfiguration, serverID: UUID) async throws -> String

    /// Reads access token, refreshes if expired. Returns nil if no token stored.
    func validToken(for serverID: UUID) async throws -> String?

    /// Deletes all OAuth tokens for a server.
    func clearTokens(for serverID: UUID)
}

// MARK: - Implementation

final class DefaultMCPOAuthService: MCPOAuthService, @unchecked Sendable {
    private let keychainService: any KeychainService
    private let urlSession: URLSession
    /// RFC 8252 §7.1 — authorization servers may require reverse-DNS-shaped
    /// (dotted) custom schemes.
    static let redirectURI = "ai.eigin://oauth/callback"

    init(keychainService: any KeychainService, urlSession: URLSession = .shared) {
        self.keychainService = keychainService
        self.urlSession = urlSession
    }

    // MARK: - Discovery

    func discoverOAuth(for serverURL: URL) async throws -> OAuthConfiguration? {
        // Probe the server with a POST to see if it requires auth
        var probeRequest = URLRequest(url: serverURL)
        probeRequest.httpMethod = "POST"
        probeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Send a minimal JSON-RPC request body so the server has something to parse
        probeRequest.httpBody = Data(#"{"jsonrpc":"2.0","method":"initialize","id":1}"#.utf8)

        let (_, probeResponse) = try await urlSession.data(for: probeRequest)
        guard let httpResponse = probeResponse as? HTTPURLResponse else {
            return nil
        }

        // If not 401, server is open
        guard httpResponse.statusCode == 401 else {
            return nil
        }

        // Parse WWW-Authenticate header for resource_metadata URL
        let wwwAuth = httpResponse.value(forHTTPHeaderField: "WWW-Authenticate") ?? ""
        let resourceMetadataURL: URL = if let extracted = extractBearerParam(
            from: wwwAuth,
            name: "resource_metadata"
        ),
            let url = URL(string: extracted)
        {
            url
        } else {
            // Fallback: construct well-known URL from server origin
            protectedResourceMetadataURL(for: serverURL)
        }

        // Fetch Protected Resource Metadata
        let (resourceData, resourceResponse) = try await urlSession.data(from: resourceMetadataURL)
        let resourceMeta: ProtectedResourceMetadata
        do {
            resourceMeta = try JSONDecoder().decode(
                ProtectedResourceMetadata.self,
                from: resourceData
            )
        } catch {
            let status = (resourceResponse as? HTTPURLResponse)?.statusCode ?? 0
            throw MCPOAuthError.metadataDiscoveryFailed(
                describeFailure(
                    status: status,
                    body: resourceData,
                    context: "protected resource metadata"
                )
            )
        }

        guard let authServers = resourceMeta.authorizationServers, !authServers.isEmpty else {
            throw MCPOAuthError.noAuthorizationServers
        }

        guard let authServerBase = URL(string: authServers[0]) else {
            throw MCPOAuthError.metadataDiscoveryFailed("Invalid authorization server URL")
        }

        // Fetch Authorization Server Metadata (RFC 8414), fallback to OpenID Configuration
        let authServerMeta: AuthorizationServerMetadata
        do {
            authServerMeta = try await fetchAuthServerMetadata(issuer: authServerBase)
        } catch let error as MCPOAuthError {
            throw error
        } catch {
            throw MCPOAuthError.metadataDiscoveryFailed(
                "Authorization server metadata fetch failed: \(error.localizedDescription)"
            )
        }

        guard let authEndpoint = URL(string: authServerMeta.authorizationEndpoint),
              let tokenEndpoint = URL(string: authServerMeta.tokenEndpoint)
        else {
            throw MCPOAuthError.metadataDiscoveryFailed("Invalid authorization/token endpoint URLs")
        }

        // Dynamic Client Registration if supported. Register with the same
        // scopes the authorization step will request, so the server can't
        // shrink them at registration time.
        var clientID: String?
        var clientSecret: String?

        if let registrationEndpoint = authServerMeta.registrationEndpoint,
           let registrationURL = URL(string: registrationEndpoint)
        {
            let registration = try await registerClient(
                at: registrationURL,
                scopes: authServerMeta.scopesSupported
            )
            clientID = registration.clientId
            clientSecret = registration.clientSecret
        }

        return OAuthConfiguration(
            resourceURL: serverURL,
            authorizationEndpoint: authEndpoint,
            tokenEndpoint: tokenEndpoint,
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: authServerMeta.scopesSupported
        )
    }

    // MARK: - Authorization

    func authorize(config: OAuthConfiguration, serverID: UUID) async throws -> String {
        guard let clientID = config.clientID else {
            throw MCPOAuthError.authorizationFailed("Client credentials are required")
        }

        // Delegates the PKCE mechanics (browser, callback, code exchange) to the
        // shared flow. The callback scheme is derived from the redirect URI so
        // it can't drift; the `resource` indicator rides along as a flow param.
        let flowConfig = PKCEOAuthConfig(
            authorizationEndpoint: config.authorizationEndpoint,
            tokenEndpoint: config.tokenEndpoint,
            clientID: clientID,
            clientSecret: config.clientSecret,
            scopes: config.scopes ?? [],
            redirectURI: Self.redirectURI,
            extraAuthorizationParams: ["resource": config.resourceURL.absoluteString],
            extraTokenParams: ["resource": config.resourceURL.absoluteString]
        )

        let tokenResponse: TokenResponse
        do {
            tokenResponse = try await PKCEOAuthFlow.authorize(
                config: flowConfig,
                urlSession: urlSession
            )
        } catch PKCEOAuthFlow.FlowError.userCancelled {
            throw MCPOAuthError.userCancelled
        } catch let error as PKCEOAuthFlow.FlowError {
            throw MCPOAuthError.authorizationFailed(error.localizedDescription)
        }

        // Store tokens in Keychain
        storeTokens(tokenResponse, config: config, serverID: serverID)

        return tokenResponse.accessToken
    }

    // MARK: - Token Validation

    func validToken(for serverID: UUID) async throws -> String? {
        guard let accessToken = readKeychain(serverID: serverID, suffix: "access_token") else {
            return nil
        }

        // Check expiry
        if let expiryString = readKeychain(serverID: serverID, suffix: "token_expiry"),
           let expiry = ISO8601DateFormatter().date(from: expiryString)
        {
            if expiry.timeIntervalSinceNow > 60 {
                // Token still valid (>60s remaining)
                return accessToken
            }
        } else {
            // No expiry stored — assume token is valid
            return accessToken
        }

        // Token expired — try refresh
        guard let refreshToken = readKeychain(serverID: serverID, suffix: "refresh_token"),
              let tokenEndpointString = readKeychain(serverID: serverID, suffix: "token_endpoint"),
              let tokenEndpoint = URL(string: tokenEndpointString),
              let clientID = readKeychain(serverID: serverID, suffix: "client_id")
        else {
            // Can't refresh — clear stale tokens
            clearTokens(for: serverID)
            return nil
        }

        let clientSecret = readKeychain(serverID: serverID, suffix: "client_secret")
        let resource = readKeychain(serverID: serverID, suffix: "resource")

        let refreshConfig = PKCEOAuthConfig(
            authorizationEndpoint: tokenEndpoint, // not used for refresh
            tokenEndpoint: tokenEndpoint,
            clientID: clientID,
            clientSecret: clientSecret,
            extraTokenParams: resource.map { ["resource": $0] } ?? [:]
        )
        let tokenResponse: TokenResponse
        do {
            tokenResponse = try await PKCEOAuthFlow.refresh(
                refreshToken: refreshToken,
                config: refreshConfig,
                urlSession: urlSession
            )
        } catch let error as PKCEOAuthFlow.FlowError {
            throw MCPOAuthError.tokenRefreshFailed(error.localizedDescription)
        }

        // Re-store with updated tokens — reconstruct a minimal config for storage
        let config = OAuthConfiguration(
            resourceURL: URL(string: resource ?? "")!,
            authorizationEndpoint: tokenEndpoint, // not used for storage
            tokenEndpoint: tokenEndpoint,
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: nil
        )
        storeTokens(tokenResponse, config: config, serverID: serverID)

        return tokenResponse.accessToken
    }

    // MARK: - Cleanup

    func clearTokens(for serverID: UUID) {
        for suffix in MCPServer.keychainSuffixes {
            keychainService.delete(key: keychainService.mcpKey(for: serverID, suffix: suffix))
        }
    }

    // MARK: - Private Helpers

    private func fetchAuthServerMetadata(issuer: URL) async throws -> AuthorizationServerMetadata {
        // Upgrade to HTTPS — issuers from authorization_servers may advertise http://
        var httpsIssuer = issuer
        if issuer.scheme == "http", var components = URLComponents(
            url: issuer,
            resolvingAgainstBaseURL: false
        ) {
            components.scheme = "https"
            httpsIssuer = components.url ?? issuer
        }

        // Try RFC 8414 first, then OpenID Configuration (per MCP spec)
        var lastFailure: String?
        for url in [
            authServerMetadataURL(for: httpsIssuer),
            httpsIssuer.appendingPathComponent(".well-known/openid-configuration"),
        ] {
            do {
                let meta = try await fetchAndDecode(AuthorizationServerMetadata.self, from: url)
                return meta.upgradingHTTP()
            } catch {
                lastFailure = error.localizedDescription
            }
        }

        throw MCPOAuthError.metadataDiscoveryFailed(
            "Could not fetch authorization server metadata: \(lastFailure ?? "unknown error")"
        )
    }

    private func registerClient(
        at endpoint: URL,
        scopes: [String]?
    ) async throws -> ClientRegistrationResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "client_name": "Eigin",
            "redirect_uris": [Self.redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "token_endpoint_auth_method": "none",
        ]
        if let scopes, !scopes.isEmpty {
            body["scope"] = scopes.joined(separator: " ")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MCPOAuthError.registrationFailed(
                describeFailure(status: status, body: data, context: "client registration")
            )
        }

        return try JSONDecoder().decode(ClientRegistrationResponse.self, from: data)
    }

    /// Human-readable failure detail from a metadata/registration response.
    /// These bodies contain no secrets (no tokens are involved), so they are
    /// safe to show and log.
    private func describeFailure(status: Int, body: Data, context: String) -> String {
        let bodyText = String(data: body, encoding: .utf8) ?? ""
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = trimmed.count > 300 ? "\(trimmed.prefix(300))…" : trimmed
        if capped.isEmpty {
            return "HTTP \(status) during \(context)"
        }
        return "HTTP \(status) during \(context): \(capped)"
    }

    private func storeTokens(
        _ response: TokenResponse,
        config: OAuthConfiguration,
        serverID: UUID
    ) {
        saveKeychain(serverID: serverID, suffix: "access_token", value: response.accessToken)

        if let refreshToken = response.refreshToken {
            saveKeychain(serverID: serverID, suffix: "refresh_token", value: refreshToken)
        }

        if let expiresIn = response.expiresIn {
            let expiry = Date.now.addingTimeInterval(TimeInterval(expiresIn))
            saveKeychain(
                serverID: serverID,
                suffix: "token_expiry",
                value: ISO8601DateFormatter().string(from: expiry)
            )
        }

        saveKeychain(
            serverID: serverID,
            suffix: "token_endpoint",
            value: config.tokenEndpoint.absoluteString
        )
        if let clientID = config.clientID {
            saveKeychain(serverID: serverID, suffix: "client_id", value: clientID)
        }

        if let secret = config.clientSecret {
            saveKeychain(serverID: serverID, suffix: "client_secret", value: secret)
        }

        saveKeychain(
            serverID: serverID,
            suffix: "resource",
            value: config.resourceURL.absoluteString
        )
    }

    // MARK: - Keychain Helpers

    private func readKeychain(serverID: UUID, suffix: String) -> String? {
        keychainService.read(key: keychainService.mcpKey(for: serverID, suffix: suffix))
    }

    private func saveKeychain(serverID: UUID, suffix: String, value: String) {
        keychainService.save(
            key: keychainService.mcpKey(for: serverID, suffix: suffix),
            value: value
        )
    }

    // MARK: - Network Helpers

    private func fetchAndDecode<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await urlSession.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw MCPOAuthError.metadataDiscoveryFailed(
                describeFailure(
                    status: http.statusCode,
                    body: data,
                    context: "metadata at \(url.absoluteString)"
                )
            )
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - URL Helpers

/// Constructs `/.well-known/oauth-protected-resource` URL from a server origin.
private func protectedResourceMetadataURL(for serverURL: URL) -> URL {
    var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
    components.path = "/.well-known/oauth-protected-resource"
    components.query = nil
    components.fragment = nil
    return components.url!
}

/// Constructs RFC 8414 authorization server metadata URL.
/// Handles path-based issuers per RFC 8414 Section 3.
private func authServerMetadataURL(for issuer: URL) -> URL {
    var components = URLComponents(url: issuer, resolvingAgainstBaseURL: false)!
    let path = components.path
    if path.isEmpty || path == "/" {
        components.path = "/.well-known/oauth-authorization-server"
    } else {
        // RFC 8414: insert .well-known before the path
        components.path = "/.well-known/oauth-authorization-server\(path)"
    }
    components.query = nil
    components.fragment = nil
    return components.url!
}

/// Parses a named parameter from a `WWW-Authenticate: Bearer ...` header value.
private func extractBearerParam(from header: String, name: String) -> String? {
    // Match: name="value" or name=value
    let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"="?([^",\s]+)"?"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(
              in: header,
              range: NSRange(header.startIndex..., in: header)
          ),
          let range = Range(match.range(at: 1), in: header)
    else {
        return nil
    }
    return String(header[range])
}
