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
    private static let redirectURI = "eigin://oauth/callback"

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
        let (resourceData, _) = try await urlSession.data(from: resourceMetadataURL)
        let resourceMeta: ProtectedResourceMetadata
        do {
            resourceMeta = try JSONDecoder().decode(
                ProtectedResourceMetadata.self,
                from: resourceData
            )
        } catch {
            throw MCPOAuthError.metadataDiscoveryFailed("Invalid protected resource metadata")
        }

        guard let authServers = resourceMeta.authorizationServers, !authServers.isEmpty else {
            throw MCPOAuthError.noAuthorizationServers
        }

        guard let authServerBase = URL(string: authServers[0]) else {
            throw MCPOAuthError.metadataDiscoveryFailed("Invalid authorization server URL")
        }

        // Fetch Authorization Server Metadata (RFC 8414), fallback to OpenID Configuration
        let authServerMeta = try await fetchAuthServerMetadata(issuer: authServerBase)

        guard let authEndpoint = URL(string: authServerMeta.authorizationEndpoint),
              let tokenEndpoint = URL(string: authServerMeta.tokenEndpoint)
        else {
            throw MCPOAuthError.metadataDiscoveryFailed("Invalid authorization/token endpoint URLs")
        }

        // Dynamic Client Registration if supported
        var clientID: String?
        var clientSecret: String?

        if let registrationEndpoint = authServerMeta.registrationEndpoint,
           let registrationURL = URL(string: registrationEndpoint)
        {
            let registration = try await registerClient(at: registrationURL, serverURL: serverURL)
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

        // Generate PKCE
        let codeVerifier = PKCEUtilities.generateCodeVerifier()
        let codeChallenge = PKCEUtilities.generateCodeChallenge(from: codeVerifier)
        let state = PKCEUtilities.generateState()

        // Build authorization URL
        var components = URLComponents(
            url: config.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: config.resourceURL.absoluteString),
        ]
        if let scopes = config.scopes, !scopes.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: scopes.joined(separator: " ")))
        }
        components.queryItems = queryItems

        guard let authURL = components.url else {
            throw MCPOAuthError.authorizationFailed("Failed to build authorization URL")
        }

        // Present browser
        let callbackURL: URL
        do {
            callbackURL = try await PKCEUtilities.presentAuthSession(url: authURL)
        } catch PKCEUtilities.AuthSessionError.userCancelled {
            throw MCPOAuthError.userCancelled
        } catch let error as PKCEUtilities.AuthSessionError {
            throw MCPOAuthError.authorizationFailed(error.localizedDescription)
        }

        // Parse callback
        guard let callbackComponents = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw MCPOAuthError.authorizationFailed("Invalid callback URL")
        }

        let params = callbackComponents.queryItems ?? []
        let returnedState = params.first(where: { $0.name == "state" })?.value
        let code = params.first(where: { $0.name == "code" })?.value
        let error = params.first(where: { $0.name == "error" })?.value

        if let error {
            throw MCPOAuthError.authorizationFailed(error)
        }

        guard returnedState == state else {
            throw MCPOAuthError.authorizationFailed("State mismatch")
        }

        guard let code else {
            throw MCPOAuthError.authorizationFailed("No authorization code received")
        }

        // Exchange code for tokens
        let tokenResponse = try await exchangeCode(
            code: code,
            codeVerifier: codeVerifier,
            config: config
        )

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

        let tokenResponse = try await refreshAccessToken(
            refreshToken: refreshToken,
            tokenEndpoint: tokenEndpoint,
            clientID: clientID,
            clientSecret: clientSecret,
            resource: resource
        )

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
        // Try RFC 8414 first
        let rfc8414URL = authServerMetadataURL(for: issuer)
        if let meta = try? await fetchAndDecode(
            AuthorizationServerMetadata.self,
            from: rfc8414URL
        ) {
            return meta
        }

        // Fallback: OpenID Configuration (per MCP spec)
        let openIDURL = issuer.appendingPathComponent(".well-known/openid-configuration")
        if let meta = try? await fetchAndDecode(AuthorizationServerMetadata.self, from: openIDURL) {
            return meta
        }

        throw MCPOAuthError.metadataDiscoveryFailed("Could not fetch authorization server metadata")
    }

    private func registerClient(
        at endpoint: URL,
        serverURL: URL
    ) async throws -> ClientRegistrationResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_name": "Eigin",
            "redirect_uris": [Self.redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "token_endpoint_auth_method": "none",
            "scope": "mcp",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw MCPOAuthError.registrationFailed("Server returned error")
        }

        return try JSONDecoder().decode(ClientRegistrationResponse.self, from: data)
    }

    private func exchangeCode(
        code: String,
        codeVerifier: String,
        config: OAuthConfiguration
    ) async throws -> TokenResponse {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": config.clientID!,
            "code_verifier": codeVerifier,
            "resource": config.resourceURL.absoluteString,
        ]
        if let secret = config.clientSecret {
            params["client_secret"] = secret
        }
        request.httpBody = formEncode(params).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw MCPOAuthError.authorizationFailed("Token exchange failed")
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func refreshAccessToken(
        refreshToken: String,
        tokenEndpoint: URL,
        clientID: String,
        clientSecret: String?,
        resource: String?
    ) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        if let secret = clientSecret {
            params["client_secret"] = secret
        }
        if let resource {
            params["resource"] = resource
        }
        request.httpBody = formEncode(params).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw MCPOAuthError.tokenRefreshFailed("Server returned error")
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
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
        let (data, _) = try await urlSession.data(from: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let escapedKey = key
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
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
