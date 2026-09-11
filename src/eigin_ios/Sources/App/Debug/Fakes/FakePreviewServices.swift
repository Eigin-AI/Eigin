import Foundation

// Preview-service fakes, extracted from \`PreviewHelpers\` (issue #228:
// every fake lives in one folder). Registered by \`PreviewEnvironment\` and
// reused by the screenshot installer.

/// A fake keychain service for previews that returns a dummy key for any provider.
struct PreviewKeychainService: KeychainService {
    func save(key: String, value: String) {}
    func read(key: String) -> String? {
        "fake-api-key"
    }

    func delete(key: String) {}
    func providerKey(for providerID: UUID) -> String {
        "fake.\(providerID)"
    }

    func mcpKey(for serverID: UUID, suffix: String) -> String {
        "fake.mcp.\(serverID).\(suffix)"
    }

    func integrationKey(for integrationID: UUID, suffix: String) -> String {
        "fake.integration.\(integrationID).\(suffix)"
    }

    var creditWalletsKey: String {
        "fake.credits.wallets"
    }
}

/// A fake OAuth service for previews.
struct PreviewMCPOAuthService: MCPOAuthService {
    func discoverOAuth(for serverURL: URL) async throws -> OAuthConfiguration? {
        nil
    }

    func authorize(config: OAuthConfiguration, serverID: UUID) async throws -> String {
        "fake-token"
    }

    func validToken(for serverID: UUID) async throws -> String? {
        "fake-token"
    }

    func clearTokens(for serverID: UUID) {}
}

/// An integration OAuth service for previews that resolves instantly with a
/// dummy token, without a browser session.
struct PreviewIntegrationOAuthService: IntegrationOAuthService {
    func authorize(config _: PKCEOAuthConfig, integrationID _: UUID) async throws -> String {
        "fake-token"
    }

    func validToken(config _: PKCEOAuthConfig, integrationID _: UUID) async throws -> String? {
        "fake-token"
    }

    func grantedScopes(for _: UUID) -> Set<String> {
        []
    }

    func clearTokens(for _: UUID) {}

    func hasStoredTokens(for _: UUID) -> Bool {
        true
    }
}

/// A credit wallet manager for previews that holds one sample wallet and never hits the relay.
struct PreviewCreditWalletManager: CreditWalletManager {
    func wallets() -> [CreditWallet] {
        [
            CreditWallet(
                token: "eict_preview",
                credits: 1240,
                status: .active,
                productID: nil,
                updatedAt: Date()
            ),
        ]
    }

    func add(_ wallet: CreditWallet) {}
    func spendableWallet() -> CreditWallet? {
        wallets().first
    }

    func evictEmpty() {}
    func refreshBalances() async {}

    func withCredits<T: Sendable>(
        _ operation: @Sendable (String) async throws -> T
    ) async throws -> T {
        try await operation("eict_preview")
    }
}

/// A credits service for previews that vends a sample catalog without StoreKit or the relay.
struct PreviewCreditsService: CreditsService {
    func availableProducts() async throws -> [PurchasableCredit] {
        [
            PurchasableCredit(
                id: "eigin.credits.v1.apple.500",
                credits: 500,
                displayName: "500 Credits",
                displayPrice: "€5.49"
            ),
            PurchasableCredit(
                id: "eigin.credits.v1.apple.1200",
                credits: 1200,
                displayName: "1,200 Credits",
                displayPrice: "€12.99"
            ),
            PurchasableCredit(
                id: "eigin.credits.v1.apple.3000",
                credits: 3000,
                displayName: "3,000 Credits",
                displayPrice: "€29.99"
            ),
        ]
    }

    func purchaseCredits(productID: String) async throws -> CreditWallet {
        CreditWallet(
            token: "eict_preview",
            credits: 500,
            status: .active,
            productID: productID,
            updatedAt: Date()
        )
    }

    func startOutstandingRedemption() async {
        // Previews have no StoreKit queue to recover.
    }

    func restorePurchases() async throws -> [CreditWallet] {
        // Previews have no purchase history to restore.
        []
    }
}

/// A model refresher for previews. Behavior is driven entirely by the provider's own cache so it
/// resolves identically no matter which preview is showing (no cross-preview contamination):
/// a provider with cached models echoes them instantly, while an empty provider simulates a slow
/// first-connect that discovers a small catalog — exercising the picker's loading state.
@MainActor
struct PreviewProviderModelRefresher: ProviderModelRefresher {
    @discardableResult
    func refresh(_ provider: Provider, apiKeyOverride _: String?) async throws -> [String] {
        if provider.availableModels.isEmpty {
            try? await Task.sleep(for: .seconds(2))
            provider.availableModels = ["gpt-5.5", "claude-sonnet-4-6", "gemini-3.5-flash"]
            provider.updatedAt = .now
            return provider.availableModels
        }
        provider.updatedAt = .now
        return provider.availableModels
    }
}
