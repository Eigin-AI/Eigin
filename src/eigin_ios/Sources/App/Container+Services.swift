import Factory
import Foundation
import SwiftData

extension Container {
    // MARK: - Infrastructure

    var keychainService: Factory<any KeychainService> {
        self { DefaultKeychainService(serviceKey: AppKeys.keychainServiceName) }.singleton
    }

    var modelContainer: Factory<ModelContainer> {
        self {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            try? FileManager.default.createDirectory(
                at: appSupport,
                withIntermediateDirectories: true
            )
            return try! ModelContainer(
                for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
                migrationPlan: EiginMigrationPlan.self
            )
        }.singleton
    }

    // MARK: - View singletons

    /// View-reachable singletons behind @Injected, so tests and screenshot
    /// scenes override them like any other service.
    @MainActor
    var gemmaModelManager: Factory<any GemmaModelManaging> {
        self { @MainActor in
            GemmaModelManager.shared
        }.singleton
    }

    @MainActor
    var integrationHealthMonitor: Factory<any IntegrationHealthMonitoring> {
        self { @MainActor in
            IntegrationHealthMonitor.shared
        }.singleton
    }

    @MainActor
    var tabBarVisibility: Factory<TabBarVisibility> {
        self { @MainActor in
            TabBarVisibility.shared
        }.singleton
    }

    var markdownDocumentCache: Factory<MarkdownDocumentCache> {
        self { .shared }.singleton
    }

    // MARK: - Speech Engine

    /// Every downloadable on-device asset: the local model plus all voice
    /// engine models. The single source for the Local assets screen.
    @MainActor
    var localAssets: Factory<[any OnDemandAsset]> {
        self { @MainActor in
            [GemmaModelManager.shared] + Container.shared.speechEngineResolver().allAssets()
        }.singleton
    }

    @MainActor
    var speechEngineResolver: Factory<SpeechEngineResolver> {
        self { @MainActor in
#if !targetEnvironment(simulator)
            let pocketTTSManager = PocketTTSModelManager()
            pocketTTSManager.checkAvailability()
            let pocketTTSProvider = PocketTTSEngineProvider(modelManager: pocketTTSManager)

            let plaprePicoManager = PlaprePicoModelManager()
            plaprePicoManager.checkAvailability()
            let plaprePicoProvider = PlaprePicoEngineProvider(modelManager: plaprePicoManager)

            return SpeechEngineResolver(
                providers: [plaprePicoProvider, pocketTTSProvider, SystemEngineProvider()]
            )
#else
            return SpeechEngineResolver(providers: [SystemEngineProvider()])
#endif
        }.singleton
    }

    // MARK: - Audio Services

    @MainActor
    var voiceService: Factory<any VoiceService> {
        self { @MainActor in
            let voices = DefaultVoiceService()
            voices.resolver = Container.shared.speechEngineResolver()
            return voices
        }.singleton
    }

    @MainActor
    var speechService: Factory<any SpeechService> {
        self { @MainActor in
            DefaultSpeechService(resolver: Container.shared.speechEngineResolver())
        }.singleton
    }

    @MainActor
    var dictationService: Factory<any DictationService> {
        self { @MainActor in DefaultDictationService() }.singleton
    }

    // MARK: - App Services

    var languageManager: Factory<LanguageManager> {
        self { LanguageManager() }.singleton
    }

    // MARK: - Chat & Provider

    var chatService: Factory<any ChatService> {
        self { DefaultChatService(keychainService: self.keychainService()) }.singleton
    }

    var networkReachability: Factory<any NetworkReachability> {
        self { DefaultNetworkReachability() }.singleton
    }

    var modelRouter: Factory<any ModelRouter> {
        self {
            DefaultModelRouter(
                reachability: self.networkReachability(),
                localModelReadiness: { GemmaModelStore.isDownloaded }
            )
        }.singleton
    }

    var imageCache: Factory<ImageCache> {
        self { ImageCache() }.singleton
    }

    var chatAttachmentStore: Factory<any ChatAttachmentStoring> {
        self {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            let root = appSupport.appendingPathComponent("ChatAttachments")
            return DefaultChatAttachmentStore(root: root)
        }.singleton
    }

    var modelMetadataService: Factory<any ModelMetadataService> {
        self { CatalogModelMetadataService() }.singleton
    }

    @MainActor
    var providerModelRefresher: Factory<any ProviderModelRefresher> {
        self { @MainActor in
            DefaultProviderModelRefresher(keychainService: self.keychainService())
        }.singleton
    }

    var vocabularyStore: Factory<any VocabularyStore> {
        self { DefaultVocabularyStore() }.singleton
    }

    // MARK: - Knowledge & Intent

    var knowledgeService: Factory<any KnowledgeService> {
        self { DefaultKnowledgeService(modelContainer: self.modelContainer()) }.singleton
    }

    var intentService: Factory<any IntentService> {
        self { DefaultIntentService(modelContainer: self.modelContainer()) }.singleton
    }

    // MARK: - Schedule & Health

    var calendarService: Factory<any CalendarService> {
        self { DefaultCalendarService() }.singleton
    }

    var reminderService: Factory<any ReminderService> {
        self { DefaultReminderService() }.singleton
    }

    var healthService: Factory<any HealthService> {
        self { DefaultHealthService() }.singleton
    }

    // MARK: - Relay & Credits

    var relayClient: Factory<any RelayClient> {
        self { DefaultRelayClient() }.singleton
    }

    var storeKitPurchaseService: Factory<any StoreKitPurchaseService> {
        self { DefaultStoreKitPurchaseService() }.singleton
    }

    var creditWalletManager: Factory<any CreditWalletManager> {
        self {
            DefaultCreditWalletManager(
                relayClient: self.relayClient(),
                keychain: self.keychainService()
            )
        }.singleton
    }

    var creditsService: Factory<any CreditsService> {
        self {
            DefaultCreditsService(
                relayClient: self.relayClient(),
                purchaseService: self.storeKitPurchaseService(),
                walletManager: self.creditWalletManager()
            )
        }.singleton
    }

    // MARK: - MCP

    var mcpOAuthService: Factory<any MCPOAuthService> {
        self { DefaultMCPOAuthService(keychainService: self.keychainService()) }.singleton
    }

    var mcpServerManager: Factory<MCPServerManager> {
        self {
            MCPServerManager(
                keychainService: self.keychainService(),
                oauthService: self.mcpOAuthService()
            )
        }.singleton
    }

    // MARK: - Integrations

    var integrationOAuthService: Factory<any IntegrationOAuthService> {
        self { DefaultIntegrationOAuthService(keychainService: self.keychainService()) }.singleton
    }

    var imapCredentialStore: Factory<any IMAPCredentialStore> {
        self { DefaultIMAPCredentialStore(keychainService: self.keychainService()) }.singleton
    }

    var aulaCredentialStore: Factory<any AulaCredentialStore> {
        self { DefaultAulaCredentialStore(keychainService: self.keychainService()) }.singleton
    }

    @MainActor
    var integrationManager: Factory<IntegrationManager> {
        self { @MainActor in
            IntegrationManager(
                oauthService: self.integrationOAuthService(),
                imapCredentialStore: self.imapCredentialStore(),
                aulaCredentialStore: self.aulaCredentialStore()
            )
        }.singleton
    }

    // MARK: - Watch

    var watchLink: Factory<WatchLink> {
        self { WatchLink() }.singleton
    }
}
