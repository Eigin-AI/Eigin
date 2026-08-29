@testable import Eigin
import Foundation
import Testing

@Suite("IntegrationOAuthService")
struct IntegrationOAuthServiceTests {
    private func makeConfig(tokenEndpoint: String) -> PKCEOAuthConfig {
        PKCEOAuthConfig(
            authorizationEndpoint: URL(string: "https://example.com/auth")!,
            tokenEndpoint: URL(string: tokenEndpoint)!,
            clientID: "client-123"
        )
    }

    @Test func validTokenReturnsNilWhenNothingStored() async throws {
        let service = DefaultIntegrationOAuthService(keychainService: FakeKeychainService())
        let token = try await service.validToken(
            config: makeConfig(tokenEndpoint: "https://example.com/token"),
            integrationID: UUID()
        )
        #expect(token == nil)
    }

    @Test func validTokenReturnsStoredTokenWhenNotExpired() async throws {
        let keychain = FakeKeychainService()
        let service = DefaultIntegrationOAuthService(keychainService: keychain)
        let id = UUID()
        let future = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(3600))
        keychain.save(
            key: keychain.integrationKey(for: id, suffix: "access_token"),
            value: "stored-token"
        )
        keychain.save(key: keychain.integrationKey(for: id, suffix: "token_expiry"), value: future)

        let token = try await service.validToken(
            config: makeConfig(tokenEndpoint: "https://example.com/token"),
            integrationID: id
        )
        #expect(token == "stored-token")
    }

    @Test func validTokenRefreshesWhenExpired() async throws {
        let keychain = FakeKeychainService()
        let session = FakeURLProtocol.fakeSession()
        let service = DefaultIntegrationOAuthService(keychainService: keychain, urlSession: session)
        let id = UUID()
        let past = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-3600))
        keychain.save(
            key: keychain.integrationKey(for: id, suffix: "access_token"),
            value: "old-token"
        )
        keychain.save(key: keychain.integrationKey(for: id, suffix: "token_expiry"), value: past)
        keychain.save(
            key: keychain.integrationKey(for: id, suffix: "refresh_token"),
            value: "refresh-abc"
        )

        let tokenEndpoint = "https://example.com/refresh-token"
        FakeURLProtocol.stubResponse(
            for: tokenEndpoint,
            data: Data(#"{"access_token":"new-token","token_type":"Bearer","expires_in":3600}"#
                .utf8),
            statusCode: 200
        )

        let token = try await service.validToken(
            config: makeConfig(tokenEndpoint: tokenEndpoint),
            integrationID: id
        )
        #expect(token == "new-token")
        #expect(keychain
            .read(key: keychain.integrationKey(for: id, suffix: "access_token")) == "new-token")
    }

    @Test func validTokenClearsAndReturnsNilWhenRefreshFails() async throws {
        let keychain = FakeKeychainService()
        let session = FakeURLProtocol.fakeSession()
        let service = DefaultIntegrationOAuthService(keychainService: keychain, urlSession: session)
        let id = UUID()
        let past = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-3600))
        keychain.save(
            key: keychain.integrationKey(for: id, suffix: "access_token"),
            value: "old-token"
        )
        keychain.save(key: keychain.integrationKey(for: id, suffix: "token_expiry"), value: past)
        keychain.save(
            key: keychain.integrationKey(for: id, suffix: "refresh_token"),
            value: "refresh-abc"
        )

        let tokenEndpoint = "https://example.com/refresh-fail"
        FakeURLProtocol.stubResponse(for: tokenEndpoint, data: Data(), statusCode: 401)

        let token = try await service.validToken(
            config: makeConfig(tokenEndpoint: tokenEndpoint),
            integrationID: id
        )
        #expect(token == nil)
        #expect(keychain.read(key: keychain.integrationKey(for: id, suffix: "access_token")) == nil)
    }

    @Test func hasStoredTokensReflectsTheAccessTokensPresence() {
        let keychain = FakeKeychainService()
        let service = DefaultIntegrationOAuthService(keychainService: keychain)
        let id = UUID()

        #expect(service.hasStoredTokens(for: id) == false)

        keychain.save(
            key: keychain.integrationKey(for: id, suffix: "access_token"),
            value: "tok"
        )
        #expect(service.hasStoredTokens(for: id) == true)

        service.clearTokens(for: id)
        #expect(service.hasStoredTokens(for: id) == false)
    }

    @Test func clearTokensRemovesAllSuffixes() {
        let keychain = FakeKeychainService()
        let service = DefaultIntegrationOAuthService(keychainService: keychain)
        let id = UUID()
        let suffixes = ["access_token", "refresh_token", "token_expiry", "scope"]
        for suffix in suffixes {
            keychain.save(key: keychain.integrationKey(for: id, suffix: suffix), value: "x")
        }

        service.clearTokens(for: id)

        for suffix in suffixes {
            #expect(keychain.read(key: keychain.integrationKey(for: id, suffix: suffix)) == nil)
        }
    }
}
