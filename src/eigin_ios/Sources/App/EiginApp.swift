import Factory
import SwiftData
import SwiftUI
import UserNotifications

/// App entry point. Initializes all services and injects them into the view hierarchy.
@main
struct EiginApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeManager = ThemeManager()

    init() {
#if EIGIN_DEV
        // Screenshot automation: seizes the launch before any service
        // resolves, so it can register fakes and a seeded store instead.
        ScreenshotMode.activateIfNeeded()
#endif

        UserDefaults.standard.register(defaults: [
            StorageKey.logSinkToFile: true,
        ])

        PendingDestinationMigrator.migrateLegacyKeys()

        FontRegistration.register()
        FontRegistration.configureNavigationBar()

        // Eagerly initialize the shared CallManager so its CXProvider is
        // registered with the telephony system before the first call.
        _ = CallManager.shared

        // Activate WatchConnectivity so a wrist tap can wake the app and ask
        // a question while the phone is pocketed.
        Container.shared.watchBridge().activate()

        // Recover purchases interrupted before their credits were redeemed: StoreKit re-delivers
        // unfinished transactions, and this sweep redeems and finishes them for the app lifetime.
        Task {
            await Container.shared.creditsService().startOutstandingRedemption()
        }

        // Register background prompt task and notification delegate.
        let container = Container.shared.modelContainer()
        BackgroundPromptScheduler.register(container: container)
        let notificationDelegate = NotificationDelegate(modelContainer: container)
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        self.notificationDelegate = notificationDelegate

        // Register notification category for Communication Notifications.
        let communicationCategory = UNNotificationCategory(
            identifier: CommunicationNotificationContent.categoryIdentifier,
            actions: [],
            intentIdentifiers: ["INSendMessageIntent"],
            options: []
        )
        center.setNotificationCategories([communicationCategory])

        AppLogger.info("App initialized", category: .general)
    }

    /// Retained so the delegate stays alive for the app lifetime.
    private let notificationDelegate: NotificationDelegate

    @AppStorage(StorageKey.onboardingComplete) private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            let languageManager = Container.shared.languageManager()
            launchRoot
                // Force a full view tree rebuild when the language changes so all
                // Localized.X.y computed properties are re-read with the new bundle.
                .id(languageManager.currentLanguage)
                .onOpenURL { url in
                    // Widget-extension handoff: everything the app can do with a route
                    // flows through the pending store, so `open` just launches.
                    if let route = EiginRoute(url: url), route != .openApp {
                        PendingDestination.set(.newChat(route))
                    }
                }
                .resolveTheme()
                .environment(\.themeManager, themeManager)
                .environment(\.locale, Locale(identifier: languageManager.currentLanguage.rawValue))
        }
        .modelContainer(launchContainer)
    }

    /// The normal app root. Screenshot mode (dev target only) stages a scene
    /// root over it.
    @ViewBuilder
    private var defaultRoot: some View {
        if onboardingComplete {
            ContentView()
        } else {
            OnboardingFlow()
        }
    }

    @ViewBuilder
    private var launchRoot: some View {
#if EIGIN_DEV
        if let sceneRoot = ScreenshotMode.sceneRoot {
            sceneRoot
        } else {
            defaultRoot
        }
#else
        defaultRoot
#endif
    }

    /// The shared store. Screenshot mode (dev target only) swaps in a seeded
    /// in-memory store.
    private var launchContainer: ModelContainer {
#if EIGIN_DEV
        if let staged = ScreenshotMode.modelContainer { return staged }
#endif
        return Container.shared.modelContainer()
    }
}
