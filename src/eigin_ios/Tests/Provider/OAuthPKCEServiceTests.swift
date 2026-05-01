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
}
