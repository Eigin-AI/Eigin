import AppIntents
import Foundation

/// Opens the app at the chat list, nothing pre-armed. Used by the widget's
/// logo button, which exists for branding, not behavior.
struct OpenEiginIntent: AppIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "intents.openApp.title"
    static let description = IntentDescription("intents.openApp.description")
    static let supportedModes: IntentModes = [.foreground(.dynamic), .background]

    func perform() async throws -> some IntentResult {
        try await bringAppForward()
        return .result()
    }
}

/// Starts a fresh chat. Shared by widget, Spotlight, Siri, and the icon menu.
///
/// The intents carry no logic: `perform` only requests the foreground
/// transition — as part of it, the system runs `ContentView`'s
/// `onAppIntentExecution` closures in the app process, and those own the
/// navigation.
struct NewChatIntent: AppIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "intents.newChat.title"
    static let description = IntentDescription("intents.newChat.description")
    static let supportedModes: IntentModes = [.foreground(.dynamic), .background]

    func perform() async throws -> some IntentResult {
        try await bringAppForward()
        return .result()
    }
}

/// Starts a fresh chat with dictation already armed.
struct DictationChatIntent: AppIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "intents.dictationChat.title"
    static let description = IntentDescription("intents.dictationChat.description")
    static let supportedModes: IntentModes = [.foreground(.dynamic), .background]

    func perform() async throws -> some IntentResult {
        try await bringAppForward()
        return .result()
    }
}

/// Starts a fresh chat dropped straight into a live call.
struct LiveCallChatIntent: AppIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "intents.liveCallChat.title"
    static let description = IntentDescription("intents.liveCallChat.description")
    static let supportedModes: IntentModes = [.foreground(.dynamic), .background]

    func perform() async throws -> some IntentResult {
        try await bringAppForward()
        return .result()
    }
}

/// Starts a fresh chat with the camera ready to attach a photo.
struct PhotoChatIntent: AppIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "intents.photoChat.title"
    static let description = IntentDescription("intents.photoChat.description")
    static let supportedModes: IntentModes = [.foreground(.dynamic), .background]

    func perform() async throws -> some IntentResult {
        try await bringAppForward()
        return .result()
    }
}

private extension AppIntent {
    /// Asks the system to bring the app forward. `.foreground(.dynamic)` leaves
    /// that decision to the intent — without this call nothing foregrounds the
    /// app and the in-app execution closures never run. No-ops in modes that
    /// can't foreground (e.g. eyes-free Siri).
    func bringAppForward() async throws {
        guard systemContext.currentMode.canContinueInForeground else { return }
        try await continueInForeground(alwaysConfirm: false)
    }
}
