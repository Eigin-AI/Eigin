import Factory
import SwiftData
import SwiftUI

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
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
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
