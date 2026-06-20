@testable import Eigin
import Foundation
import Testing

@Suite("OAuthPKCEService")
struct OAuthPKCEServiceTests {
    @Test func codeVerifierIsBase64URLEncoded() {
        let verifier = PKCEUtilities.generateCodeVerifier()
        #expect(!verifier.isEmpty)
        #expect(!verifier.contains("+"))
        #expect(!verifier.contains("/"))
        #expect(!verifier.contains("="))
    }

    @Test func codeChallengeIsDeterministic() {
        let verifier = "test-verifier-value"
        let challenge1 = PKCEUtilities.generateCodeChallenge(from: verifier)
        let challenge2 = PKCEUtilities.generateCodeChallenge(from: verifier)
        #expect(challenge1 == challenge2)
        #expect(!challenge1.isEmpty)
    }

    @Test func codeChallengeVariesWithVerifier() {
        let challenge1 = PKCEUtilities.generateCodeChallenge(from: "verifier-a")
        let challenge2 = PKCEUtilities.generateCodeChallenge(from: "verifier-b")
        #expect(challenge1 != challenge2)
    }

    @Test func stateIsUnique() {
        let state1 = PKCEUtilities.generateState()
        let state2 = PKCEUtilities.generateState()
        #expect(state1 != state2)
    }

    @Test func openRouterPresetHasCorrectOAuthURLs() throws {
        let preset = try #require(ProviderPreset.all.first { $0.id == "openrouter" })
        #expect(preset.authMethod == .oAuthPKCE)
        #expect(preset.oAuthAuthorizationURL == "https://openrouter.ai/auth")
        #expect(preset.oAuthTokenExchangeURL == "https://openrouter.ai/api/v1/auth/keys")
    }

    @Test func eurouterPresetHasCorrectOAuthURLs() throws {
        let preset = try #require(ProviderPreset.all.first { $0.id == "eurouter" })
        #expect(preset.authMethod == .oAuthPKCE)
        #expect(preset.oAuthAuthorizationURL == "https://api.eurouter.ai/api/v1/auth")
        #expect(preset.oAuthTokenExchangeURL == "https://api.eurouter.ai/api/v1/auth/keys")
    }

    @Test func handleCallbackRejectsMismatchedState() async throws {
        let service = try DefaultOAuthPKCEService(
            authorizationURL: #require(URL(string: "https://example.com/auth")),
            tokenExchangeURL: #require(URL(string: "https://example.com/exchange"))
        )

        let callback =
            try #require(URL(string: "eigin://oauth/callback?code=abc123&state=wrong-state"))

        await #expect(throws: OAuthPKCEError.authorizationFailed("State mismatch")) {
            try await service.handleCallback(
                callback,
                codeVerifier: "verifier",
                expectedState: "expected-state"
            )
        }
    }

    @Test func handleCallbackRejectsErrorParameter() async throws {
        let service = try DefaultOAuthPKCEService(
            authorizationURL: #require(URL(string: "https://example.com/auth")),
            tokenExchangeURL: #require(URL(string: "https://example.com/exchange"))
        )

        let callback =
            try #require(
                URL(string: "eigin://oauth/callback?error=access_denied&state=expected-state")
            )

        await #expect(throws: OAuthPKCEError.authorizationFailed("access_denied")) {
            try await service.handleCallback(
                callback,
                codeVerifier: "verifier",
                expectedState: "expected-state"
            )
        }
    }

    @Test func handleCallbackAcceptsMatchingStateAndExchangesCode() async throws {
        let exchangeURL = "https://example.com/exchange"
        let session = FakeURLProtocol.fakeSession()
        let service = try DefaultOAuthPKCEService(
            authorizationURL: #require(URL(string: "https://example.com/auth")),
            tokenExchangeURL: #require(URL(string: exchangeURL)),
            urlSession: session
        )

        let keyResponse = Data(#"{"key":"test-api-key-123"}"#.utf8)
        FakeURLProtocol.stubResponse(for: exchangeURL, data: keyResponse, statusCode: 200)

        let callback =
            try #require(URL(string: "eigin://oauth/callback?code=abc123&state=expected-state"))
        let key = try await service.handleCallback(
            callback,
            codeVerifier: "verifier",
            expectedState: "expected-state"
        )

        #expect(key == "test-api-key-123")
    }
}
