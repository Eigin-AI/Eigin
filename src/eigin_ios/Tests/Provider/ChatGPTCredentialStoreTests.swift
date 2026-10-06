@testable import Eigin
import Foundation
import Testing

@Suite("ChatGPTCredentialStore")
struct ChatGPTCredentialStoreTests {
    private let keychain = FakeKeychainService()
    private let providerID = UUID()

    private func makeStore(
        refresh: (@Sendable (UUID, String) async throws -> RefreshedCredentialTokens)?
    ) async -> DefaultChatGPTCredentialStore {
        let store = DefaultChatGPTCredentialStore(
            keychain: keychain,
            serviceKey: "test.\(UUID().uuidString)",
            customRefresh: refresh
        )
        await store.save(
            ChatGPTCredential(
                clientID: "oaiapp_test",
                accessToken: "expired-token",
                refreshToken: "rot-1",
                idToken: "id-jwt",
                expiry: .distantPast,
                scopes: [ChatGPTSignInConstants.planUsageScope]
            ),
            providerID: providerID
        )
        return store
    }

    @Test func validAccessTokenSkipsRefreshWhenNotExpired() async {
        let store = DefaultChatGPTCredentialStore(
            keychain: keychain,
            serviceKey: "test.\(UUID().uuidString)",
            customRefresh: { _, _ in
                Issue.record("Refresh should not run for a fresh token")
                throw CredentialRefreshError.transient("should not refresh")
            }
        )
        await store.save(
            ChatGPTCredential(
                clientID: "oaiapp_test",
                accessToken: "fresh-token",
                refreshToken: "rot-1",
                idToken: "id-jwt",
                expiry: Date.now.addingTimeInterval(3600),
                scopes: []
            ),
            providerID: providerID
        )
        let token = await store.validAccessToken(providerID: providerID)
        #expect(token == "fresh-token")
    }

    @Test func expiredTokenRefreshesAndRotates() async {
        let counter = RefreshCounter()
        let store = await makeStore { _, refreshToken in
            await counter.bump()
            #expect(refreshToken == "rot-1")
            return RefreshedCredentialTokens(
                accessToken: "new-token",
                refreshToken: "rot-2",
                expiresIn: 3600,
                scope: "openid"
            )
        }

        let token = await store.validAccessToken(providerID: providerID)

        #expect(token == "new-token")
        #expect(await counter.count == 1)
        // Rotation persisted: the next refresh carries the new token.
        #expect(keychain.read(
            key: keychain.providerKey(for: providerID, suffix: "refresh_token")
        ) == "rot-2")
    }

    @Test func unreadableExpiryForcesRefreshInsteadOfTrustingToken() async {
        let counter = RefreshCounter()
        let store = await makeStore { _, _ in
            await counter.bump()
            return RefreshedCredentialTokens(
                accessToken: "new-token",
                refreshToken: "rot-2",
                expiresIn: 3600,
                scope: nil
            )
        }
        // A corrupt (unparseable) expiry must not silently trust the stored
        // token forever — the store refreshes instead.
        keychain.save(
            key: keychain.providerKey(for: providerID, suffix: "token_expiry"),
            value: "not-a-date"
        )

        let token = await store.validAccessToken(providerID: providerID)

        #expect(token == "new-token")
        #expect(await counter.count == 1)
    }

    @Test func terminalRefreshFailureClearsTokensButKeepsIdentity() async {
        let store = await makeStore { _, _ in
            throw CredentialRefreshError.terminal("invalid_grant")
        }

        let token = await store.validAccessToken(providerID: providerID)

        #expect(token == nil)
        // The issued client ID and retained ID token survive: they're what the
        // "sign in again" flow reuses (id_token_hint skips account selection).
        #expect(await store.clientID(providerID: providerID) == "oaiapp_test")
        // The token pair itself is gone — the durable "sign in again" signal.
        #expect(keychain.read(
            key: keychain.providerKey(for: providerID, suffix: "access_token")
        ) == nil)
        #expect(keychain.read(
            key: keychain.providerKey(for: providerID, suffix: "refresh_token")
        ) == nil)
    }

    @Test func transientRefreshFailureKeepsCredential() async {
        let store = await makeStore { _, _ in
            throw CredentialRefreshError.transient("network down")
        }

        let token = await store.validAccessToken(providerID: providerID)

        #expect(token == nil)
        #expect(await store.clientID(providerID: providerID) == "oaiapp_test")
    }

    @Test func concurrentReadsShareOneRefresh() async {
        let counter = RefreshCounter()
        let store = await makeStore { _, _ in
            await counter.bump()
            // Make the refresh slow so concurrent callers overlap.
            try await Task.sleep(for: .milliseconds(100))
            return RefreshedCredentialTokens(
                accessToken: "new-token",
                refreshToken: "rot-2",
                expiresIn: 3600,
                scope: nil
            )
        }

        let tokens = await withTaskGroup(of: String?.self) { group in
            for _ in 0 ..< 10 {
                group.addTask {
                    await store.validAccessToken(providerID: providerID)
                }
            }
            var results: [String?] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        #expect(tokens.allSatisfy { $0 == "new-token" })
        #expect(await counter.count == 1)
    }

    @Test func hostIDIsStableAcrossCalls() async {
        let store = DefaultChatGPTCredentialStore(
            keychain: keychain,
            serviceKey: "test.\(UUID().uuidString)"
        )
        let first = await store.hostID()
        let second = await store.hostID()
        #expect(first != nil)
        #expect(first == second)
        #expect(first?.hasPrefix("urn:uuid:") == true)
        // RFC 9562 §5.4 — lowercase; OpenAI rejects uppercase host IDs.
        #expect(first == first?.lowercased())
    }

    @Test func hostIDNormalizesLegacyUppercaseUUIDs() async {
        let store = DefaultChatGPTCredentialStore(
            keychain: keychain,
            serviceKey: "test.\(UUID().uuidString)"
        )
        await keychain.save(
            key: store.hostIDKey,
            value: "urn:uuid:62667209-DC9E-4240-88F2-BD9305A72DD0"
        )

        let hostID = await store.hostID()

        #expect(hostID == "urn:uuid:62667209-dc9e-4240-88f2-bd9305a72dd0")
        #expect(await store.hostID() == hostID)
    }
}

/// Thread-safe refresh-call counter for the single-flight test.
private actor RefreshCounter {
    private(set) var count = 0

    func bump() {
        count += 1
    }

    // MARK: - Refresh error taxonomy (ChatGPTTokenRefresh.perform)

    /// Drives the real SIWC refresh grant against a stubbed token endpoint.
    private func performRefresh(statusCode: Int, body: String) async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: ChatGPTSignInConstants.tokenURL.absoluteString,
            data: Data(body.utf8),
            statusCode: statusCode
        )
        _ = try await ChatGPTTokenRefresh.perform(
            refreshToken: "rot-1",
            clientID: "oaiapp_test",
            urlSession: session
        )
    }

    @Test func refreshRateLimitIsTransient() async throws {
        do {
            _ = try await performRefresh(
                statusCode: 429,
                body: #"{"error":"rate_limited","message":"slow down"}"#
            )
            Issue.record("Expected transient")
        } catch let error as CredentialRefreshError {
            #expect(error == .transient("HTTP 429"))
        }
    }

    @Test func refreshServerOutageIsTransient() async throws {
        do {
            _ = try await performRefresh(
                statusCode: 503,
                body: #"{"error":"server_error"}"#
            )
            Issue.record("Expected transient")
        } catch let error as CredentialRefreshError {
            #expect(error == .transient("HTTP 503"))
        }
    }

    @Test func refreshInvalidGrantIsTerminal() async throws {
        do {
            _ = try await performRefresh(
                statusCode: 400,
                body: #"{"error":"invalid_grant","message":"token revoked"}"#
            )
            Issue.record("Expected terminal")
        } catch let error as CredentialRefreshError {
            #expect(error ==
                .terminal("HTTP 400 {\"error\":\"invalid_grant\",\"message\":\"token revoked\"}"))
        }
    }
}
