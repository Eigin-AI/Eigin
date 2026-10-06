import Foundation

/// Resolves the refreshable credential store a provider needs, by provider.
///
/// Most providers carry a static keychain API key and resolve to no store.
/// A provider with a refreshable OAuth credential (ChatGPT subscription
/// sign-in today; the next subscription provider is one case here, not a
/// new injection into every consumer) maps to its store.
protocol ProviderCredentialResolving: Sendable {
    /// The refreshable credential store for this baseURL, or `nil` when the
    /// provider doesn't carry one (static or no key).
    func store(for baseURL: String, providerID: UUID) -> (any ProviderCredentialStoring)?
}

struct DefaultProviderCredentialResolver: ProviderCredentialResolving {
    private let chatGPT: any ProviderCredentialStoring

    init(chatGPT: any ProviderCredentialStoring) {
        self.chatGPT = chatGPT
    }

    func store(for baseURL: String, providerID _: UUID) -> (any ProviderCredentialStoring)? {
        if ProviderPreset.isChatGPTSubscription(baseURL) {
            return chatGPT
        }
        return nil
    }
}
