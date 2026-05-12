import Factory
import SwiftData
import SwiftUI
import UserNotifications

/// App entry point. Initializes all services and injects them into the view hierarchy.
@main
struct EiginApp: App {
    @State private var themeManager = ThemeManager()

    init() {
        FontRegistration.register()
        FontRegistration.configureNavigationBar()

        // Eagerly initialize the shared CallManager so its CXProvider is
        // registered with the telephony system before the first call.
        _ = CallManager.shared

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
            Group {
                if onboardingComplete {
                    ContentView()
                } else {
                    OnboardingFlow()
                }
            }
            // Force a full view tree rebuild when the language changes so all
            // Localized.X.y computed properties are re-read with the new bundle.
            .id(languageManager.currentLanguage)
            .resolveTheme()
            .environment(\.themeManager, themeManager)
            .environment(\.locale, Locale(identifier: languageManager.currentLanguage.rawValue))
        }
        .modelContainer(Container.shared.modelContainer())
    }
}
