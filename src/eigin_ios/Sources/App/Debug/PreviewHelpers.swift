import Factory
import SwiftData
import SwiftUI

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

/// View modifier that sets up a complete preview environment with fake services
/// and a sample provider in an in-memory SwiftData store.
struct PreviewEnvironment: ViewModifier {
    let container: ModelContainer

    /// - Parameter seed: Extra sample data for one preview's own screen,
    ///   inserted after the shared fixtures.
    init(seed: ((ModelContext) -> Void)? = nil) {
        // Register preview fakes on the Factory container.
        Container.shared.keychainService.register { PreviewKeychainService() }
        Container.shared.chatService.register { PreviewChatService() }
        Container.shared.modelMetadataService.register { CatalogModelMetadataService() }
        Container.shared.providerModelRefresher.register { PreviewProviderModelRefresher() }
        Container.shared.mcpOAuthService.register { PreviewMCPOAuthService() }
        Container.shared.mcpServerManager.register {
            MCPServerManager(
                keychainService: PreviewKeychainService(),
                oauthService: PreviewMCPOAuthService()
            )
        }
        Container.shared.creditWalletManager.register { PreviewCreditWalletManager() }
        Container.shared.creditsService.register { PreviewCreditsService() }
        Container.shared.integrationOAuthService.register { PreviewIntegrationOAuthService() }

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Matches the schema `CurrentModels` resolves to, so the container
        // holds every model a view can query.
        let container = try! ModelContainer(
            for: Schema(SchemaV6.models, version: SchemaV6.versionIdentifier),
            configurations: config
        )

        let sampleProvider = Provider(name: "Preview Provider", baseURL: "https://fake.local")
        sampleProvider.availableModels = ["gpt-4o", "gpt-4o-mini", "claude-3.5-sonnet"]
        sampleProvider.enabledModels = ["gpt-4o", "gpt-4o-mini", "claude-3.5-sonnet"]
        container.mainContext.insert(sampleProvider)

        let sampleAgent = Agent(name: "Eigin", providerID: sampleProvider.id, model: "gpt-4o")
        sampleAgent.emoji = "🧠"
        sampleAgent.identityCore = "I am Eigin, a helpful assistant for software development."
        sampleAgent.userCore = "The user is a developer working on iOS apps."
        sampleAgent.soulCore = ""
        sampleAgent.bootstrapComplete = true
        container.mainContext.insert(sampleAgent)

        let sampleSpace = Space(agentID: sampleAgent.id)
        sampleSpace.name = "iOS Project"
        sampleSpace.emoji = "📱"
        sampleSpace.bootstrapComplete = true
        container.mainContext.insert(sampleSpace)

        let sampleChat = Chat(agentID: sampleAgent.id, title: "iOS development tips")
        sampleChat.spaceID = sampleSpace.id
        container.mainContext.insert(sampleChat)

        let msg1 = Message(role: "user", content: "What's the best way to structure a SwiftUI app?")
        msg1.chat = sampleChat
        container.mainContext.insert(msg1)

        let msg2 = Message(
            role: "assistant",
            content: "A common approach is to use a layer-first structure with Models, Services, and Views as top-level folders."
        )
        msg2.chat = sampleChat
        container.mainContext.insert(msg2)

        seed?(container.mainContext)

        self.container = container
    }

    func body(content: Content) -> some View {
        content
            .modelContainer(container)
            .resolveTheme()
            .environment(\.themeManager, ThemeManager())
    }
}

extension View {
    /// Wraps the view in a full preview environment with fake services and sample data.
    ///
    /// - Parameter seed: Optional extra sample data for this specific preview.
    func previewEnvironment(seed: ((ModelContext) -> Void)? = nil) -> some View {
        modifier(PreviewEnvironment(seed: seed))
    }
}

/// Sample connected integrations for previewing the integrations UI. Google and
/// IMAP share the Email category, giving it the two providers the
/// active-provider radio needs.
enum PreviewIntegrations {
    static func seedConnected(_ context: ModelContext) {
        context.insert(
            Integration(
                typeID: "google",
                accountLabel: "daniel@gmail.com",
                grantedCapabilities: [Capability.email.rawValue]
            )
        )
        context.insert(
            Integration(
                typeID: "imap",
                accountLabel: "daniel@eigin.ai",
                grantedCapabilities: [Capability.email.rawValue]
            )
        )
        context.insert(
            Integration(
                typeID: "aula",
                accountLabel: "Ada",
                grantedCapabilities: [Capability.aula.rawValue]
            )
        )
    }
}
