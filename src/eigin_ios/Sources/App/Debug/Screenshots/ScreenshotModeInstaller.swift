import Factory
import SwiftData
import SwiftUI

/// Replaces the app's launch with a fully seeded, fake-backed screenshot scene.
///
/// Looked up by name from the app shell (`ScreenshotMode` in
/// `Sources/App/ScreenshotMode.swift`). Lives in `Sources/App/Debug/Screenshots`,
/// which is compiled into `EiginDev` only, so demo code never ships in the
/// App Store target.
@MainActor
@objcMembers
final class ScreenshotModeInstaller: NSObject, ScreenshotModeInstalling {
    static func activate(scenario: String) {
        guard let scene = ScreenshotScene(rawValue: scenario) else {
            // Falling through would capture the real app and upload it as a
            // store screenshot, so a typo has to stop the run.
            fatalError("Unknown screenshot scenario: \(scenario)")
        }

        ScreenshotModeInstaller().install(scene: scene)
    }

    private func install(scene: ScreenshotScene) {
        // Deterministic captures: no launch animations, no onboarding.
        UIView.setAnimationsEnabled(false)
        UserDefaults.standard.set(true, forKey: StorageKey.onboardingComplete)

        Self.registerFakes()

        // The real model can't run on the simulator: scenes see it as ready.
        Container.shared.gemmaModelManager.register { @MainActor in
            FakeGemmaModelManager(state: .ready)
        }
        Container.shared.integrationHealthMonitor.register { @MainActor in
            FakeIntegrationHealthMonitor()
        }

        let container = try! ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // Any service resolving the container through Factory gets the same
        // seeded store (only the app shell reads the bridge directly).
        Container.shared.modelContainer.register { container }

        let context = container.mainContext
        let fixtures = ScreenshotFixtures.seed(into: context)
        if let chatTitle = scene.chatTitle {
            // A header chat for the canvas scenes; the conversation itself is
            // composed as view-only items (see ScreenshotCanvas).
            ScreenshotFixtures.chat(
                context,
                agent: fixtures.agent,
                spaceID: fixtures.space.id,
                title: chatTitle
            )
        }
        try? context.save()

        // Fakes resolve through the container; no root-level overrides needed.
        ScreenshotMode.stage(
            root: AnyView(
                ScreenshotSceneRoot(
                    scene: scene,
                    chat: firstChat(in: context),
                    agentEmoji: fixtures.agent.emoji
                )
            ),
            container: container
        )
    }

    private func firstChat(in context: ModelContext) -> Chat? {
        try? context.fetch(FetchDescriptor<Chat>()).first
    }

    /// Fakes for everything that could reach the network, StoreKit, or system
    /// permissions while a scene renders. Previews share most of them.
    private static func registerFakes() {
        Container.shared.keychainService.register { PreviewKeychainService() }
        Container.shared.chatService.register { PreviewChatService() }
        Container.shared.providerModelRefresher.register { PreviewProviderModelRefresher() }
        Container.shared.creditWalletManager.register { PreviewCreditWalletManager() }
        Container.shared.creditsService.register { PreviewCreditsService() }
        Container.shared.mcpOAuthService.register { PreviewMCPOAuthService() }
        Container.shared.integrationOAuthService.register { PreviewIntegrationOAuthService() }

        Container.shared.relayClient.register { FakeRelayClient() }
        Container.shared.calendarService.register { FakeCalendarService() }
        Container.shared.reminderService.register { FakeReminderService() }
        Container.shared.healthService.register { FakeHealthService() }
        Container.shared.storeKitPurchaseService.register { FakeStoreKitPurchaseService() }
    }
}
