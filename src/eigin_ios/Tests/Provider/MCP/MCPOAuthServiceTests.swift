@testable import Eigin
import Foundation
import Testing

@Suite("MCPOAuthService discovery", .serialized)
struct MCPOAuthServiceTests {
    private let serverURL = URL(string: "https://mcp.example.com/mcp")!
    private let resourceMetadataURL = "https://mcp.example.com/.well-known/oauth-protected-resource"
    private let authServerMetadataURL = "https://auth.example.com/.well-known/oauth-authorization-server"
    private let registrationURL = "https://auth.example.com/oauth/register"

    /// Mimics a spec-compliant OAuth-protected MCP server: 401 probe →
    /// resource metadata → AS metadata → dynamic registration.
    private func stubOAuthChain(registrationStatus: Int, registrationBody: Data) {
        FakeURLProtocol.stubResponse(for: serverURL.absoluteString, data: Data(), statusCode: 401)
        FakeURLProtocol.stubResponse(
            for: resourceMetadataURL,
            data: Data(#"{"authorization_servers":["https://auth.example.com"]}"#.utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: authServerMetadataURL,
            data: Data(
                #"{"authorization_endpoint":"https://auth.example.com/oauth/authorize","token_endpoint":"https://auth.example.com/oauth/token","registration_endpoint":"\#(registrationURL)","scopes_supported":["mcp:tools:read","mcp:tools:call"]}"#
                    .utf8
            ),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: registrationURL,
            data: registrationBody,
            statusCode: registrationStatus
        )
    }

    private func makeService() -> DefaultMCPOAuthService {
        DefaultMCPOAuthService(
            keychainService: FakeKeychainService(),
            urlSession: FakeURLProtocol.fakeSession()
        )
    }

    @Test func redirectSchemeIsReverseDNSShaped() {
        // RFC 8252 §7.1: some servers (Comfy Cloud) reject custom schemes
        // without a dot. This is the root cause of #249. The callback scheme
        // the browser session waits on is derived from this URI's scheme.
        let redirect = MCPOAuthCallback.app.redirectURI
        let scheme = URL(string: redirect)?.scheme ?? ""
        #expect(scheme.contains("."))
        #expect(redirect.hasSuffix("://oauth/callback"))
    }

    @Test(arguments: [
        "https://mcp.basecamp.com/mcp", "https://MCP.BASECAMP.COM:443/mcp/",
        "https://mcp.basecamp.com/mcp/extra", "https://mcp.basecamp.com/%6dcp",
    ])
    func basecampRegistersHTTPSCallback(endpoint: String) async throws {
        stubOAuthChain(
            registrationStatus: 201,
            registrationBody: Data(#"{"client_id":"basecamp-client"}"#.utf8)
        )
        FakeURLProtocol.stubResponse(for: endpoint, data: Data(), statusCode: 401)
        FakeURLProtocol.stubResponse(
            for: "https://mcp.basecamp.com/.well-known/oauth-protected-resource",
            data: Data(#"{"authorization_servers":["https://auth.example.com"]}"#.utf8),
            statusCode: 200
        )
        let url = try #require(URL(string: endpoint))
        // Discovery keeps the original origin when constructing metadata URLs.
        var metadata = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        metadata.path = "/.well-known/oauth-protected-resource"
        try FakeURLProtocol.stubResponse(
            for: #require(metadata.url?.absoluteString),
            data: Data(#"{"authorization_servers":["https://auth.example.com"]}"#
                .utf8),
            statusCode: 200
        )
        let config = try #require(try await makeService().discoverOAuth(for: url))
        let body = try #require(FakeURLProtocol.lastRequestBody(for: registrationURL))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["redirect_uris"] as? [String] == ["https://auth.eigin.ai/callback/"])
        #expect(config.callback.redirectURI == "https://auth.eigin.ai/callback/")
        #expect(config.callback.callbackScheme == "eigin")
        let registeredRedirect = try #require((json["redirect_uris"] as? [String])?.first)
        let tokenURL = config.tokenEndpoint.absoluteString
        FakeURLProtocol.stubResponse(
            for: tokenURL,
            data: Data(#"{"access_token":"basecamp-token","token_type":"Bearer","expires_in":3600}"#
                .utf8),
            statusCode: 200
        )
        let service = DefaultMCPOAuthService(
            keychainService: FakeKeychainService(), urlSession: FakeURLProtocol.fakeSession(),
            presentAuthSession: { authorizationURL, scheme in
                let items = try #require(URLComponents(
                    url: authorizationURL,
                    resolvingAgainstBaseURL: false
                )?.queryItems)
                #expect(items.first { $0.name == "redirect_uri" }?.value == registeredRedirect)
                #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
                #expect(items.first { $0.name == "code_challenge" }?.value?.isEmpty == false)
                #expect(scheme == "eigin")
                let state = try #require(items.first { $0.name == "state" }?.value)
                var callback = URLComponents(string: "eigin://oauth/callback")!
                callback.queryItems = [
                    URLQueryItem(name: "code", value: "test-code"),
                    URLQueryItem(name: "state", value: state),
                ]
                return try #require(callback.url)
            }
        )
        let serverID = UUID()
        let token = try await service.authorize(config: config, serverID: serverID)
        #expect(token == "basecamp-token")
        #expect(try await service.validToken(for: serverID) == token)
        let exchangeBody = try #require(FakeURLProtocol.lastRequestBody(for: tokenURL))
        var exchange = URLComponents()
        exchange.percentEncodedQuery = try #require(String(data: exchangeBody, encoding: .utf8))
        #expect(exchange.queryItems?.first { $0.name == "redirect_uri" }?
            .value == registeredRedirect)
        #expect(exchange.queryItems?.first { $0.name == "code" }?.value == "test-code")
        #expect(exchange.queryItems?.first { $0.name == "code_verifier" }?.value?.isEmpty == false)
        #expect(config.withClientCredentials(clientID: "manual", clientSecret: nil).callback
            .redirectURI == config.callback.redirectURI)
    }

    @Test(arguments: [true, false])
    func notionCancellationAndDenialDoNotStoreTokens(cancelled: Bool) async throws {
        let service = DefaultMCPOAuthService(
            keychainService: FakeKeychainService(), urlSession: FakeURLProtocol.fakeSession(),
            presentAuthSession: { authorizationURL, _ in
                if cancelled { throw PKCEUtilities.AuthSessionError.userCancelled }
                let items = try #require(URLComponents(
                    url: authorizationURL,
                    resolvingAgainstBaseURL: false
                )?.queryItems)
                let state = try #require(items.first { $0.name == "state" }?.value)
                var callback = URLComponents(string: "ai.eigin://oauth/callback")!
                callback.queryItems = [
                    URLQueryItem(name: "error", value: "access_denied"),
                    URLQueryItem(name: "state", value: state),
                ]
                return try #require(callback.url)
            }
        )
        let config = try OAuthConfiguration(
            resourceURL: MCPPreset.notion.endpoint,
            authorizationEndpoint: #require(URL(string: "https://mcp.notion.com/authorize")),
            tokenEndpoint: #require(URL(string: "https://mcp.notion.com/token")),
            clientID: "notion-client", clientSecret: nil, scopes: ["default"]
        )
        let serverID = UUID()
        do {
            _ = try await service.authorize(config: config, serverID: serverID)
            Issue.record("Expected authorization to fail")
        } catch let error as MCPOAuthError {
            switch error {
            case .userCancelled: #expect(cancelled)
            case .authorizationFailed(let reason):
                #expect(!cancelled)
                #expect(reason.contains("access_denied"))
            default: Issue.record("Unexpected error: \(error)")
            }
        }
        #expect(try await service.validToken(for: serverID) == nil)
    }

    @Test func notionAuthorizesAndRefreshesWithAppCallback() async throws {
        let endpoint = MCPPreset.notion.endpoint.absoluteString
        let metadataURL = "https://mcp.notion.com/.well-known/oauth-protected-resource/mcp"
        let tokenURL = "https://mcp.notion.com/token"
        let registerURL = "https://mcp.notion.com/register"
        FakeURLProtocol.stubResponse(
            for: endpoint, data: Data(), statusCode: 401,
            headers: ["WWW-Authenticate": "Bearer resource_metadata=\"\(metadataURL)\""]
        )
        FakeURLProtocol.stubResponse(
            for: metadataURL,
            data: Data(
                #"{"resource":"https://mcp.notion.com/mcp","authorization_servers":["https://mcp.notion.com"]}"#
                    .utf8
            ),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "https://mcp.notion.com/.well-known/oauth-authorization-server",
            data: Data(
                #"{"issuer":"https://mcp.notion.com","authorization_endpoint":"https://mcp.notion.com/authorize","token_endpoint":"https://mcp.notion.com/token","registration_endpoint":"https://mcp.notion.com/register","code_challenge_methods_supported":["S256"],"token_endpoint_auth_methods_supported":["none"]}"#
                    .utf8
            ),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: registerURL, data: Data(#"{"client_id":"notion-client"}"#.utf8), statusCode: 201
        )
        FakeURLProtocol.stubResponse(
            for: tokenURL,
            data: Data(
                #"{"access_token":"notion-token","refresh_token":"notion-refresh","token_type":"Bearer","expires_in":0}"#
                    .utf8
            ),
            statusCode: 200
        )
        let service = DefaultMCPOAuthService(
            keychainService: FakeKeychainService(), urlSession: FakeURLProtocol.fakeSession(),
            presentAuthSession: { authorizationURL, scheme in
                let items = try #require(URLComponents(
                    url: authorizationURL,
                    resolvingAgainstBaseURL: false
                )?.queryItems)
                #expect(scheme == "ai.eigin")
                #expect(items.first { $0.name == "redirect_uri" }?
                    .value == "ai.eigin://oauth/callback")
                #expect(items.first { $0.name == "resource" }?
                    .value == "https://mcp.notion.com/mcp")
                #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
                #expect(items.first { $0.name == "code_challenge" }?.value?.isEmpty == false)
                let state = try #require(items.first { $0.name == "state" }?.value)
                var callback = URLComponents(string: "ai.eigin://oauth/callback")!
                callback.queryItems = [
                    URLQueryItem(name: "code", value: "notion-code"),
                    URLQueryItem(name: "state", value: state),
                ]
                return try #require(callback.url)
            }
        )
        let config = try #require(try await service.discoverOAuth(for: MCPPreset.notion.endpoint))
        let registrationBody = try #require(FakeURLProtocol.lastRequestBody(for: registerURL))
        let registration = try #require(try JSONSerialization
            .jsonObject(with: registrationBody) as? [String: Any])
        #expect(registration["redirect_uris"] as? [String] == ["ai.eigin://oauth/callback"])
        #expect(registration["token_endpoint_auth_method"] as? String == "none")
        #expect(config.clientSecret == nil)
        let serverID = UUID()
        #expect(try await service.authorize(config: config, serverID: serverID) == "notion-token")
        let exchangeBody = try #require(FakeURLProtocol.lastRequestBody(for: tokenURL))
        var exchange = URLComponents()
        exchange.percentEncodedQuery = try #require(String(data: exchangeBody, encoding: .utf8))
        #expect(exchange.queryItems?.first { $0.name == "redirect_uri" }?
            .value == "ai.eigin://oauth/callback")
        #expect(exchange.queryItems?.first { $0.name == "resource" }?.value == endpoint)
        #expect(exchange.queryItems?.first { $0.name == "code_verifier" }?.value?.isEmpty == false)

        FakeURLProtocol.stubResponse(
            for: tokenURL,
            data: Data(
                #"{"access_token":"refreshed-notion-token","refresh_token":"rotated-notion-refresh","token_type":"Bearer","expires_in":3600}"#
                    .utf8
            ),
            statusCode: 200
        )
        #expect(try await service.validToken(for: serverID) == "refreshed-notion-token")
        let refreshBody = try #require(FakeURLProtocol.lastRequestBody(for: tokenURL))
        var refresh = URLComponents()
        refresh.percentEncodedQuery = try #require(String(data: refreshBody, encoding: .utf8))
        #expect(refresh.queryItems?.first { $0.name == "resource" }?.value == endpoint)
        #expect(refresh.queryItems?.first { $0.name == "grant_type" }?.value == "refresh_token")
        #expect(refresh.queryItems?.first { $0.name == "refresh_token" }?.value == "notion-refresh")
    }

    @Test(arguments: [
        "https://mcp.dinero.dk", "https://mcp.example.com/mcp",
        "https://mcp.basecamp.com.evil.example/mcp", "http://mcp.basecamp.com/mcp",
        "https://mcp.basecamp.com:444/mcp", "https://user@mcp.basecamp.com/mcp",
        "https://user:password@mcp.basecamp.com/mcp", "https://mcp.basecamp.com/mcp?x=1",
        "https://mcp.basecamp.com/mcp#fragment",
    ])
    func unrelatedEndpointsKeepAppCallback(endpoint: String) throws {
        let callback = try MCPOAuthCallback.forEndpoint(#require(URL(string: endpoint)))
        #expect(callback.redirectURI == "ai.eigin://oauth/callback")
        #expect(callback.callbackScheme == "ai.eigin")
    }

    @Test func openServerSkipsDiscovery() async throws {
        FakeURLProtocol.stubResponse(for: serverURL.absoluteString, data: Data(), statusCode: 200)
        let config = try await makeService().discoverOAuth(for: serverURL)
        #expect(config == nil)
    }

    @Test func discoveryRegistersWithRequestedScopesAndDottedRedirect() async throws {
        stubOAuthChain(
            registrationStatus: 201,
            registrationBody: Data(#"{"client_id":"client-123"}"#.utf8)
        )

        let config = try await makeService().discoverOAuth(for: serverURL)
        let registered = try #require(config)
        #expect(registered.clientID == "client-123")
        #expect(registered.scopes == ["mcp:tools:read", "mcp:tools:call"])

        // The registration body must carry the redirect we'll actually use
        // and the scopes the authorization step will request.
        let body = try #require(FakeURLProtocol.lastRequestBody(for: registrationURL))
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["redirect_uris"] as? [String] == ["ai.eigin://oauth/callback"])
        #expect(json["scope"] as? String == "mcp:tools:read mcp:tools:call")
    }

    @Test(arguments: ["https://mcp.example.com/", "https://mcp.example.com/resource"])
    func discoveryUsesAdvertisedResource(resource: String) async throws {
        let enteredURL = try #require(URL(string: "https://mcp.example.com"))
        stubOAuthChain(
            registrationStatus: 201,
            registrationBody: Data(#"{"client_id":"client-123"}"#.utf8)
        )
        FakeURLProtocol.stubResponse(for: enteredURL.absoluteString, data: Data(), statusCode: 401)
        FakeURLProtocol.stubResponse(
            for: resourceMetadataURL,
            data: Data(
                #"{"resource":"\#(resource)","authorization_servers":["https://auth.example.com"]}"#
                    .utf8
            ),
            statusCode: 200
        )

        let config = try #require(try await makeService().discoverOAuth(for: enteredURL))
        #expect(config.resourceURL.absoluteString == resource)
    }

    @Test func discoveryFallsBackToServerURLWhenResourceIsMissing() async throws {
        stubOAuthChain(
            registrationStatus: 201,
            registrationBody: Data(#"{"client_id":"client-123"}"#.utf8)
        )

        let config = try #require(try await makeService().discoverOAuth(for: serverURL))
        #expect(config.resourceURL == serverURL)
    }

    @Test(arguments: [
        "",
        "/relative",
        "https://",
        "ftp://mcp.example.com",
        "https://mcp.example.com/#fragment",
    ])
    func discoveryRejectsInvalidResource(resource: String) async throws {
        stubOAuthChain(
            registrationStatus: 201,
            registrationBody: Data(#"{"client_id":"client-123"}"#.utf8)
        )
        FakeURLProtocol.stubResponse(
            for: resourceMetadataURL,
            data: Data(
                #"{"resource":"\#(resource)","authorization_servers":["https://auth.example.com"]}"#
                    .utf8
            ),
            statusCode: 200
        )

        do {
            _ = try await makeService().discoverOAuth(for: serverURL)
            Issue.record("Expected invalid resource failure")
        } catch let error as MCPOAuthError {
            guard case .metadataDiscoveryFailed(let reason) = error else {
                Issue.record("Wrong error case: \(error)")
                return
            }
            #expect(reason.contains("resource"))
        }
    }

    @Test func registrationFailureSurfacesStatusAndBody() async throws {
        // Comfy Cloud's actual rejection of our pre-fix redirect URI.
        stubOAuthChain(
            registrationStatus: 400,
            registrationBody: Data(
                #"{"error":"invalid_redirect_uri","error_description":"scheme \"eigin\" lacks a dot"}"#
                    .utf8
            )
        )

        do {
            _ = try await makeService().discoverOAuth(for: serverURL)
            Issue.record("Expected registration failure")
        } catch let error as MCPOAuthError {
            guard case .registrationFailed(let reason) = error else {
                Issue.record("Wrong error case: \(error)")
                return
            }
            // The detail must carry the status and the server's own message —
            // that body is what identified the root cause.
            #expect(reason.contains("400"))
            #expect(reason.contains("invalid_redirect_uri"))
        }
    }

    @Test func metadataFailureSurfacesStatusAndBody() async throws {
        FakeURLProtocol.stubResponse(for: serverURL.absoluteString, data: Data(), statusCode: 401)
        FakeURLProtocol.stubResponse(
            for: resourceMetadataURL,
            data: Data("not json".utf8),
            statusCode: 500
        )

        do {
            _ = try await makeService().discoverOAuth(for: serverURL)
            Issue.record("Expected metadata failure")
        } catch let error as MCPOAuthError {
            guard case .metadataDiscoveryFailed(let reason) = error else {
                Issue.record("Wrong error case: \(error)")
                return
            }
            #expect(reason.contains("500"))
        }
    }
}
