@testable import Eigin
import Foundation
import Testing

@Suite("ChatGPTSignInService", .serialized)
struct ChatGPTSignInServiceTests {
    private let service = DefaultChatGPTSignInService(credentialStore: StubChatGPTCredentialStore())

    // MARK: - Authorize URL

    @Test func registrationURLCarriesDynamicClientAndHint() throws {
        let url = service.buildAuthorizeURL(
            clientID: ChatGPTSignInConstants.registrationClientID,
            redirectURI: "http://127.0.0.1:1455/auth/callback",
            hostID: "urn:uuid:1111",
            idTokenHint: nil,
            codeVerifier: "verifier",
            state: "state-1",
            nonce: "nonce-1"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try #require(components.queryItems)

        #expect(query.item(named: "client_id") == "dynamic_agent_client")
        #expect(query.item(named: "agent_name_hint") == ChatGPTSignInConstants.agentNameHint)
        #expect(query.item(named: "ext_agent_host_id") == "urn:uuid:1111")
        #expect(query.item(named: "response_type") == "code")
        #expect(query.item(named: "redirect_uri") == "http://127.0.0.1:1455/auth/callback")
        #expect(query.item(named: "resource") == ChatGPTSignInConstants.resource)
        #expect(query.item(named: "code_challenge_method") == "S256")
        #expect(query.item(named: "code_challenge") == PKCEUtilities
            .generateCodeChallenge(from: "verifier"))
        #expect(query.item(named: "scope")?.contains(ChatGPTSignInConstants.planUsageScope) == true)
    }

    @Test func reauthorizationURLUsesIssuedClientAndHint() throws {
        let url = service.buildAuthorizeURL(
            clientID: "oaiapp_saved",
            redirectURI: "http://127.0.0.1:54321/auth/callback",
            hostID: "urn:uuid:1111",
            idTokenHint: "old-id-jwt",
            codeVerifier: "verifier",
            state: "state-2",
            nonce: "nonce-2"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try #require(components.queryItems)

        #expect(query.item(named: "client_id") == "oaiapp_saved")
        #expect(query.item(named: "id_token_hint") == "old-id-jwt")
        // Registration metadata is only for the dynamic registration request.
        #expect(query.item(named: "agent_name_hint") == nil)
    }

    // MARK: - Callback validation

    private func callback(
        code: String? = "auth-code",
        state: String = "state-1",
        clientID: String? = "oaiapp_issued"
    ) -> URLComponents {
        var items = [URLQueryItem(name: "code", value: code)]
        items.append(URLQueryItem(name: "state", value: state))
        if let clientID {
            items.append(URLQueryItem(name: "client_id", value: clientID))
        }
        return URLComponents(string: "http://127.0.0.1:1455/auth/callback")!.with(items)
    }

    @Test func validRegistrationCallbackReturnsCodeAndIssuedClient() throws {
        let result = try service.acceptCallback(
            callback(),
            state: "state-1",
            expectedClientID: nil
        )
        #expect(result.code == "auth-code")
        #expect(result.clientID == "oaiapp_issued")
    }

    @Test func reauthorizationCallbackMayOmitClientID() throws {
        let result = try service.acceptCallback(
            callback(clientID: nil),
            state: "state-1",
            expectedClientID: "oaiapp_saved"
        )
        #expect(result.clientID == "oaiapp_saved")
    }

    @Test func stateMismatchThrows() {
        #expect(throws: ChatGPTSubscriptionError.stateMismatch.self) {
            try service.acceptCallback(callback(), state: "state-other", expectedClientID: nil)
        }
    }

    @Test func accessDeniedThrowsDeclined() throws {
        var components = callback()
        components.queryItems = [
            URLQueryItem(name: "error", value: "access_denied"),
            URLQueryItem(name: "state", value: "state-1"),
        ]
        #expect(throws: ChatGPTSubscriptionError.declined.self) {
            try service.acceptCallback(components, state: "state-1", expectedClientID: nil)
        }
    }

    @Test func registrationWithoutIssuedClientIsIncomplete() {
        #expect(throws: ChatGPTSubscriptionError.registrationIncomplete.self) {
            try service.acceptCallback(
                callback(clientID: nil),
                state: "state-1",
                expectedClientID: nil
            )
        }
    }

    @Test func differentClientIDOnReauthorizationIsRejected() {
        #expect(throws: ChatGPTSubscriptionError.clientIDMismatch.self) {
            try service.acceptCallback(
                callback(clientID: "oaiapp_other"),
                state: "state-1",
                expectedClientID: "oaiapp_saved"
            )
        }
    }

    // MARK: - Token exchange

    @Test func exchangeMapsPlanlessAccountInvalidGrantToSubscriptionRequired() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = ChatGPTSignInConstants.tokenURL.absoluteString
        FakeURLProtocol.stubResponse(
            for: url,
            data: Data(#"{"error":"invalid_grant"}"#.utf8),
            statusCode: 400
        )

        do {
            _ = try await service.exchange(
                code: "auth-code",
                clientID: "oaiapp_test",
                redirectURI: "http://127.0.0.1:1455/auth/callback",
                codeVerifier: "verifier",
                expectedNonce: "nonce-1",
                urlSession: session
            )
            Issue.record("Expected subscriptionRequired")
        } catch let error as ChatGPTSubscriptionError {
            #expect(error == .subscriptionRequired)
        }
    }

    // MARK: - Token exchange

    @Test func exchangeDeclinesIdentityOnlyResult() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = ChatGPTSignInConstants.tokenURL.absoluteString
        let body = #"{"access_token":"oat_1","refresh_token":"rot_1","id_token":"jwt","expires_in":3600,"scope":"openid profile email"}"#
        FakeURLProtocol.stubResponse(for: url, data: Data(body.utf8), statusCode: 200)

        do {
            _ = try await service.exchange(
                code: "auth-code",
                clientID: "oaiapp_issued",
                redirectURI: "http://127.0.0.1:1455/auth/callback",
                codeVerifier: "verifier",
                expectedNonce: "nonce-1",
                urlSession: session
            )
            Issue.record("Expected planUsageNotGranted")
        } catch let error as ChatGPTSubscriptionError {
            #expect(error == .planUsageNotGranted)
        }

        // The exchange is form-encoded and carries the resource.
        let request = try #require(FakeURLProtocol.lastRequest(for: url))
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.contains("application/x-www-form-urlencoded"))
        if let body = request.httpBody {
            let text = String(decoding: body, as: UTF8.self)
            #expect(text.contains("grant_type=authorization_code"))
            #expect(text.contains("resource="))
            #expect(text.contains("client_id=oaiapp_issued"))
        }
    }

    @Test func exchangeValidatesIDTokenSignature() async throws {
        let session = FakeURLProtocol.fakeSession()
        let tokenURL = ChatGPTSignInConstants.tokenURL.absoluteString
        let jwksURL = ChatGPTSignInConstants.jwksURL.absoluteString
        let body = #"{"access_token":"oat_1","refresh_token":"rot_1","id_token":"garbage.token","expires_in":3600,"scope":"chatgpt.tokens.use.direct openid"}"#
        FakeURLProtocol.stubResponse(for: tokenURL, data: Data(body.utf8), statusCode: 200)
        FakeURLProtocol.stubResponse(
            for: jwksURL,
            data: Data(#"{"keys":[]}"#.utf8),
            statusCode: 200
        )

        do {
            _ = try await service.exchange(
                code: "auth-code",
                clientID: "oaiapp_issued",
                redirectURI: "http://127.0.0.1:1455/auth/callback",
                codeVerifier: "verifier",
                expectedNonce: "nonce-1",
                urlSession: session
            )
            Issue.record("Expected idTokenValidation")
        } catch let error as ChatGPTSubscriptionError {
            #expect(error == .idTokenValidation("Malformed ID token."))
        }
    }
}

private extension URLComponents {
    func with(_ items: [URLQueryItem]) -> URLComponents {
        var copy = self
        copy.queryItems = items
        return copy
    }
}

private extension [URLQueryItem] {
    func item(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}
