@testable import Eigin
import Foundation
import Testing

/// Verifies the Infercom sign-in pieces: the RFC 8693 exchange wire format,
/// the refreshable credential store, and the credential resolver wiring.
@Suite("InfercomSignIn")
struct InfercomSignInTests {
    private let keychain = FakeKeychainService()
    private let providerID = UUID()

    // MARK: - Constants

    @Test func infercomPresetUsesSignInMethodAndKeepsAPIKeyOption() throws {
        let preset = try #require(ProviderPreset.all.first { $0.id == "infercom" })
        #expect(preset.authMethod == .infercomSignIn)
        #expect(preset.apiKeyURL != nil)
        #expect(preset.baseURL == InfercomSignInConstants.apiBaseURL)
    }

    @Test func sentinelRoundTrips() {
        #expect(ProviderPreset.isInfercomSignIn(ProviderPreset.infercomSignInBaseURL))
        #expect(!ProviderPreset.isInfercomSignIn(InfercomSignInConstants.apiBaseURL))
    }

    // MARK: - RFC 8693 token exchange

    @Test func exchangeSendsRFC8693FormFieldsWithLoginAccessToken() async throws {
        let exchangeURL = InfercomSignInConstants.exchangeEndpoint.absoluteString
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: exchangeURL,
            data: Data(#"{"access_token":"api-token","expires_in":604800}"#.utf8),
            statusCode: 200
        )

        let service = DefaultInfercomSignInService(urlSession: session)
        _ = try await service.exchange(accessToken: "login-access-token")

        let body = try #require(FakeURLProtocol.lastRequestBody(for: exchangeURL))
        let form = String(decoding: body, as: UTF8.self)
        // Colons are percent-encoded by the same encoder the shared PKCE
        // flow uses, so the RFC 8693 URNs arrive partially escaped.
        #expect(form
            .contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange"))
        #expect(form
            .contains("subject_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aaccess_token"))
        #expect(form.contains("subject_token=login-access-token"))
        #expect(form.contains("client_id=\(InfercomSignInConstants.clientID)"))
    }

    @Test func exchangeParsesAPITokenAndReadsExpiresIn() async throws {
        let exchangeURL = InfercomSignInConstants.exchangeEndpoint.absoluteString
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: exchangeURL,
            data: Data(#"{"access_token":"api-token","token_type":"Bearer","expires_in":604800}"#
                .utf8),
            statusCode: 200
        )

        let service = DefaultInfercomSignInService(urlSession: session)
        let exchanged = try await service.exchange(accessToken: "login-access-token")

        #expect(exchanged.apiToken == "api-token")
        #expect(exchanged.expiresIn == 604_800)
    }

    @Test func exchangeMapsUnverifiedIdentityToUnverifiedEmail() async {
        let exchangeURL = InfercomSignInConstants.exchangeEndpoint.absoluteString
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: exchangeURL,
            data: Data(#"{"error":"identity is not verified"}"#.utf8),
            statusCode: 400
        )

        let service = DefaultInfercomSignInService(urlSession: session)
        await #expect(throws: InfercomSignInError.unverifiedEmail) {
            try await service.exchange(accessToken: "login-access-token")
        }
    }

    @Test func exchangeMaps402ToHTTPErrorWithBody() async {
        let exchangeURL = InfercomSignInConstants.exchangeEndpoint.absoluteString
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: exchangeURL,
            data: Data(#"{"error":"PAYMENT_METHOD_REQUIRED"}"#.utf8),
            statusCode: 402
        )

        let service = DefaultInfercomSignInService(urlSession: session)
        do {
            _ = try await service.exchange(accessToken: "login-access-token")
            Issue.record("Expected httpError")
        } catch let error as InfercomSignInError {
            #expect(error == .httpError(code: 402, body: #"{"error":"PAYMENT_METHOD_REQUIRED"}"#))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Credential store

    private func makeStore(
        refresh: (@Sendable (UUID, String) async throws -> RefreshedCredentialTokens)?
    ) -> DefaultInfercomCredentialStore {
        DefaultInfercomCredentialStore(
            keychain: keychain,
            customRefresh: refresh
        )
    }

    private func saveCredential(_ store: DefaultInfercomCredentialStore) async {
        await store.save(
            InfercomCredential(
                apiToken: "expired-token",
                refreshToken: "rot-1",
                expiry: .distantPast
            ),
            providerID: providerID
        )
    }

    @Test func freshTokenSkipsRefresh() async {
        let store = makeStore { _, _ in
            Issue.record("Refresh should not run for a fresh token")
            throw CredentialRefreshError.transient("should not refresh")
        }
        await store.save(
            InfercomCredential(
                apiToken: "fresh-token",
                refreshToken: "rot-1",
                expiry: Date.now.addingTimeInterval(3600)
            ),
            providerID: providerID
        )

        let token = await store.validAccessToken(providerID: providerID)

        #expect(token == "fresh-token")
    }

    @Test func expiredTokenRefreshReExchangesAndRotates() async throws {
        let store = makeStore { [providerID] id, refreshToken in
            #expect(id == providerID)
            #expect(refreshToken == "rot-1")
            return RefreshedCredentialTokens(
                // The refresh grant's token is the *login* access token; the
                // real leg re-exchanges it. The custom closure stands in for
                // both calls, so what lands is the API token.
                accessToken: "new-api-token",
                refreshToken: "rot-2",
                expiresIn: 3600,
                scope: nil
            )
        }
        await saveCredential(store)

        let token = await store.validAccessToken(providerID: providerID)

        #expect(token == "new-api-token")
        // Rotation persisted: the next refresh carries the new token.
        #expect(keychain.read(
            key: keychain.providerKey(for: providerID, suffix: "refresh_token")
        ) == "rot-2")
        // Expiry persisted from the response's expires_in, not hardcoded.
        let expiry = keychain.read(
            key: keychain.providerKey(for: providerID, suffix: "token_expiry")
        ).flatMap { ISO8601DateFormatter().date(from: $0) }
        #expect(expiry != nil)
        #expect(try #require(expiry?.timeIntervalSinceNow) > 3000)
    }

    @Test func terminalRefreshFailureClearsCredential() async {
        let store = makeStore { _, _ in
            throw CredentialRefreshError.terminal("invalid_grant")
        }
        await saveCredential(store)

        let token = await store.validAccessToken(providerID: providerID)

        #expect(token == nil)
        #expect(keychain.read(
            key: keychain.providerKey(for: providerID, suffix: "access_token")
        ) == nil)
        #expect(keychain.read(
            key: keychain.providerKey(for: providerID, suffix: "refresh_token")
        ) == nil)
    }

    @Test func transientRefreshFailureKeepsCredential() async {
        let store = makeStore { _, _ in
            throw CredentialRefreshError.transient("HTTP 500")
        }
        await saveCredential(store)

        let token = await store.validAccessToken(providerID: providerID)

        #expect(token == nil)
        #expect(keychain.read(
            key: keychain.providerKey(for: providerID, suffix: "refresh_token")
        ) == "rot-1")
    }

    @Test func revokeAndClearRevokesStoredRefreshTokenThenClears() async {
        let revokeURL = InfercomSignInConstants.revocationEndpoint.absoluteString
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(for: revokeURL, data: Data(), statusCode: 200)
        let store = DefaultInfercomCredentialStore(keychain: keychain, urlSession: session)
        await saveCredential(store)

        await store.revokeAndClear(providerID: providerID)

        let body = FakeURLProtocol.lastRequestBody(for: revokeURL)
        let form = body.map { String(decoding: $0, as: UTF8.self) }
        #expect(form?.contains("token=rot-1") == true)
        #expect(form?.contains("client_id=\(InfercomSignInConstants.clientID)") == true)
        #expect(keychain.read(
            key: keychain.providerKey(for: providerID, suffix: "refresh_token")
        ) == nil)
    }

    @Test func clearRemovesEverySuffix() async {
        let store = makeStore(refresh: nil)
        await saveCredential(store)

        await store.clear(providerID: providerID)

        for suffix in ["access_token", "refresh_token", "token_expiry"] {
            #expect(keychain
                .read(key: keychain.providerKey(for: providerID, suffix: suffix)) == nil)
        }
    }

    // MARK: - Resolver wiring

    @Test func resolverMapsSentinelToInfercomStoreAndRealURLToNothing() {
        let chatGPT = StubChatGPTCredentialStore()
        let infercom = StubInfercomCredentialStore()
        let resolver = DefaultProviderCredentialResolver(chatGPT: chatGPT, infercom: infercom)

        #expect(
            resolver.store(
                for: ProviderPreset.infercomSignInBaseURL,
                providerID: providerID
            ) != nil
        )
        #expect(resolver
            .store(for: InfercomSignInConstants.apiBaseURL, providerID: providerID) == nil)
        #expect(
            resolver.store(
                for: "https://api.eurouter.ai/api/v1",
                providerID: providerID
            ) == nil
        )
    }

    // MARK: - Error mapping

    @Test func unverifiedEmailMapsToVerificationCard() {
        let error = ConnectionError(from: InfercomSignInError.unverifiedEmail)

        #expect(error.title == Localized.Errors.Infercom.unverifiedEmailTitle)
        #expect(error.suggestion == Localized.Errors.Infercom.unverifiedEmailSuggestion)
    }

    @Test func paymentRequiredMapsToGenericBillingCard() {
        let error = ConnectionError(
            from: InfercomSignInError.httpError(code: 402, body: nil)
        )

        #expect(error.title == Localized.Errors.Billing.required)
        #expect(error.suggestion == Localized.Errors.Provider.billingRequired)
    }
}
