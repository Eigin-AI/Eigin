@testable import Eigin
import Foundation
import Testing

@Suite("ProviderCredentials")
struct ProviderCredentialsTests {
    @Test func relayResolvesToEmptyTokenWithoutKeychainKey() {
        let keychain = FakeKeychainService()
        let token = ProviderCredentials.apiToken(
            baseURL: "eigin-relay://", providerID: UUID(), keychain: keychain
        )
        #expect(token == "")
    }

    @Test func localResolvesToEmptyToken() {
        let keychain = FakeKeychainService()
        let token = ProviderCredentials.apiToken(
            baseURL: "local://", providerID: UUID(), keychain: keychain
        )
        #expect(token == "")
    }

    @Test func cloudReturnsStoredKey() {
        let keychain = FakeKeychainService()
        let providerID = UUID()
        keychain.save(key: keychain.providerKey(for: providerID), value: "sk-123")
        let token = ProviderCredentials.apiToken(
            baseURL: "https://api.openai.com/v1", providerID: providerID, keychain: keychain
        )
        #expect(token == "sk-123")
    }

    @Test func cloudReturnsNilWhenNoKeyStored() {
        let keychain = FakeKeychainService()
        let token = ProviderCredentials.apiToken(
            baseURL: "https://api.openai.com/v1", providerID: UUID(), keychain: keychain
        )
        #expect(token == nil)
    }
}
