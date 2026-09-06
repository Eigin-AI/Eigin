/// `on-device` — a question you would not type into someone else's server.
/// The app has no local-inference indicator UI (the model picker lives in chat
/// settings), so the scene conveys locality through the conversation itself.
/// Two natural exchanges; the privacy answer closes the screen.
enum ScreenshotOnDeviceScene {
    static let chatTitle = "Tomorrow's salary talk"

    static var items: [ChatItem] {
        [
            .message(
                id: "on-device-user-1",
                role: "user",
                content: """
                I need to give a salary expectation tomorrow for the senior \
                role. What's fair in Copenhagen?
                """
            ),
            .message(
                id: "on-device-reply-1",
                role: "assistant",
                content: """
                With your eight years' experience, open at 62,000 DKK a month. \
                Most offers have room above the first number, so don't lead \
                with your ceiling.
                """
            ),
            .message(
                id: "on-device-user-2",
                role: "user",
                content: "I haven't told my manager I'm looking. This stays on my phone, right?"
            ),
            .message(
                id: "on-device-reply-2",
                role: "assistant",
                content: """
                It stays. The model runs on your device, so nothing you type \
                leaves the phone.
                """
            ),
        ]
    }
}
