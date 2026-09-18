@testable import Eigin
import Foundation
import Testing

@Suite("MCPOAuthService discovery")
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
        let redirect = DefaultMCPOAuthService.redirectURI
        let scheme = URL(string: redirect)?.scheme ?? ""
        #expect(scheme.contains("."))
        #expect(redirect.hasSuffix("://oauth/callback"))
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
