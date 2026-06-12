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

/// View modifier that sets up a complete preview environment with fake services
/// and a sample provider in an in-memory SwiftData store.
struct PreviewEnvironment: ViewModifier {
    let container: ModelContainer

    init() {
        // Register preview fakes on the Factory container.
        Container.shared.keychainService.register { PreviewKeychainService() }
        Container.shared.chatService.register { PreviewChatService() }
        Container.shared.modelMetadataService.register { CatalogModelMetadataService() }
        Container.shared.mcpOAuthService.register { PreviewMCPOAuthService() }
        Container.shared.mcpServerManager.register {
            MCPServerManager(
                keychainService: PreviewKeychainService(),
                oauthService: PreviewMCPOAuthService()
            )
        }

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Schema(SchemaV2.models, version: SchemaV2.versionIdentifier),
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
    func previewEnvironment() -> some View {
        modifier(PreviewEnvironment())
    }
}
