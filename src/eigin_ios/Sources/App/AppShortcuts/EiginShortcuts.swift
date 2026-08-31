import AppIntents

/// Registers the chat-launching intents as App Shortcuts so they surface in
/// Spotlight, Siri, the Shortcuts app, and the app icon's long-press menu —
/// without the user building anything.
///
/// `OpenEiginIntent` is deliberately excluded: tapping the app icon already
/// does the same thing.
struct EiginShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewChatIntent(),
            phrases: ["\(.applicationName) new chat"],
            shortTitle: "intents.newChat.title",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: DictationChatIntent(),
            phrases: ["\(.applicationName) dictate", "\(.applicationName) new dictation"],
            shortTitle: "intents.dictationChat.title",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: PhotoChatIntent(),
            phrases: ["\(.applicationName) photo chat"],
            shortTitle: "intents.photoChat.title",
            systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: LiveCallChatIntent(),
            phrases: ["\(.applicationName) live call", "\(.applicationName) call"],
            shortTitle: "intents.liveCallChat.title",
            systemImageName: "phone.fill"
        )
    }
}
