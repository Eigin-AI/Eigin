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

/// Both stores enter here through the shared ``ProviderCredentialStoring``
/// contract — the resolver only reads tokens and clears; it never saves, so
/// it needs no typed credential access.
struct DefaultProviderCredentialResolver: ProviderCredentialResolving {
    private let chatGPT: any ProviderCredentialStoring
    private let infercom: any ProviderCredentialStoring

    init(
        chatGPT: any ProviderCredentialStoring,
        infercom: any ProviderCredentialStoring
    ) {
        self.chatGPT = chatGPT
        self.infercom = infercom
    }

    func store(for baseURL: String, providerID _: UUID) -> (any ProviderCredentialStoring)? {
        if ProviderPreset.isChatGPTSubscription(baseURL) {
            return chatGPT
        }
        if ProviderPreset.isInfercomSignIn(baseURL) {
            return infercom
        }
        return nil
    }
}
