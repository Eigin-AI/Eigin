@testable import Eigin
import Foundation
import Testing

@Suite("ProviderCredentials")
struct ProviderCredentialsTests {
    private static let resolver =
        StubProviderCredentialResolver(chatGPT: StubChatGPTCredentialStore())

    @Test func relayResolvesToEmptyTokenWithoutKeychainKey() async {
        let keychain = FakeKeychainService()
        let token = await ProviderCredentials.apiToken(
            baseURL: "eigin-relay://",
            providerID: UUID(),
            keychain: keychain,
            credentialStores: Self.resolver
        )
        #expect(token == "")
    }

    @Test func localResolvesToEmptyToken() async {
        let keychain = FakeKeychainService()
        let token = await ProviderCredentials.apiToken(
            baseURL: "local://",
            providerID: UUID(),
            keychain: keychain,
            credentialStores: Self.resolver
        )
        #expect(token == "")
    }

    @Test func cloudReturnsStoredKey() async {
        let keychain = FakeKeychainService()
        let providerID = UUID()
        keychain.save(key: keychain.providerKey(for: providerID), value: "sk-123")
        let token = await ProviderCredentials.apiToken(
            baseURL: "https://api.openai.com/v1",
            providerID: providerID,
            keychain: keychain,
            credentialStores: Self.resolver
        )
        #expect(token == "sk-123")
    }

    @Test func cloudReturnsNilWhenNoKeyStored() async {
        let keychain = FakeKeychainService()
        let token = await ProviderCredentials.apiToken(
            baseURL: "https://api.openai.com/v1",
            providerID: UUID(),
            keychain: keychain,
            credentialStores: Self.resolver
        )
        #expect(token == nil)
    }

    // MARK: - ChatGPT sign-in

    @Test func chatGPTReturnsRefreshableToken() async {
        let store = StubChatGPTCredentialStore()
        store.stubbedToken = "oat-1"
        let resolver = StubProviderCredentialResolver(chatGPT: store)
        let token = await ProviderCredentials.apiToken(
            baseURL: "openai-chatgpt://",
            providerID: UUID(),
            keychain: FakeKeychainService(),
            credentialStores: resolver
        )
        #expect(token == "oat-1")
    }

    @Test func chatGPTReturnsNilWhenCredentialInvalid() async {
        let store = StubChatGPTCredentialStore()
        store.stubbedToken = nil
        let resolver = StubProviderCredentialResolver(chatGPT: store)
        let token = await ProviderCredentials.apiToken(
            baseURL: "openai-chatgpt://",
            providerID: UUID(),
            keychain: FakeKeychainService(),
            credentialStores: resolver
        )
        #expect(token == nil)
    }
}
