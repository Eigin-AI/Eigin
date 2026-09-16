import SwiftUI
import UserNotifications

@main
struct EiginWatchApp: App {
    @State private var model = AskModel()

    init() {
        // Registers the one font the screen uses (Typography.body).
        WatchFonts.register()
        // The answer arrives as a notification; authorization is asked once,
        // up front, so the first push-to-talk already has it.
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    var body: some Scene {
        WindowGroup {
            AskScreen(model: model)
                // The watch can't reach the user's theme choice, and watchOS
                // has no light mode, so the default theme resolves for dark.
                .environment(\.colors, DefaultTheme().colors(for: .dark))
        }
    }
}
