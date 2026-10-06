import Foundation

/// Resolves the API token a provider needs for inference.
enum ProviderCredentials {
    /// The API token to authorize requests for this provider.
    ///
    /// Relay and on-device providers carry no keychain API key (relay is authorized per-request by
    /// a credit token, on-device needs nothing), so both resolve to an empty token. Key-based cloud
    /// providers read their token from the keychain and return `nil` when none is stored. Providers
    /// with a refreshable OAuth credential get their store resolved by
    /// ``ProviderCredentialResolving``
    /// and return its (possibly refreshed) access token — `nil` there means sign in again.
    static func apiToken(
        baseURL: String,
        providerID: UUID,
        keychain: any KeychainService,
        credentialStores: any ProviderCredentialResolving
    ) async -> String? {
        if ProviderPreset.isLocal(baseURL) || ProviderPreset.isRelay(baseURL) {
            return ""
        }
        if let store = credentialStores.store(for: baseURL, providerID: providerID) {
            return await store.validAccessToken(providerID: providerID)
        }
        return keychain.read(key: keychain.providerKey(for: providerID))
    }
}
