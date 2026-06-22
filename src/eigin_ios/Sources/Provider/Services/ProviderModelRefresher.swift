import Foundation

/// Fetches a provider's current model list and writes it back to the persisted record.
///
/// This is the single place model catalogs are refreshed. The fetched list is treated as a
/// refreshable cache (``Provider/availableModels``): callers show the cached list immediately and
/// refresh in the background. Reuses ``LLMClient/fetchModels()`` for the actual network call.
@MainActor
protocol ProviderModelRefresher: Sendable {
    /// Fetches the provider's models and updates ``Provider/availableModels`` and
    /// ``Provider/updatedAt``.
    ///
    /// - Parameters:
    ///   - provider: The persisted provider record to refresh.
    ///   - apiKeyOverride: Key to use instead of the keychain value. Pass this during connect/edit
    ///     before the key is persisted; otherwise leave `nil` to read the stored key.
    /// - Returns: The refreshed model IDs.
    @discardableResult
    func refresh(_ provider: Provider, apiKeyOverride: String?) async throws -> [String]
}

extension ProviderModelRefresher {
    @discardableResult
    func refresh(_ provider: Provider) async throws -> [String] {
        try await refresh(provider, apiKeyOverride: nil)
    }
}

@MainActor
struct DefaultProviderModelRefresher: ProviderModelRefresher {
    let keychainService: any KeychainService

    @discardableResult
    func refresh(_ provider: Provider, apiKeyOverride: String?) async throws -> [String] {
        let apiKey = apiKeyOverride ?? resolveKey(for: provider)
        let client = LLMClientFactory.client(baseURL: provider.baseURL, apiToken: apiKey)
        let models = try await client.fetchModels()
        provider.availableModels = models
        provider.updatedAt = .now
        return models
    }

    /// Local and relay providers don't use a keychain key; everyone else reads theirs.
    private func resolveKey(for provider: Provider) -> String {
        if ProviderPreset.isLocal(provider.baseURL) || ProviderPreset.isRelay(provider.baseURL) {
            return ""
        }
        return keychainService.read(key: keychainService.providerKey(for: provider.id)) ?? ""
    }
}
