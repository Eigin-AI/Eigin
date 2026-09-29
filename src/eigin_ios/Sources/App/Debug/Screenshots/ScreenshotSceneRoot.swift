import SwiftData
import SwiftUI

/// Root view shown while a screenshot scene is staged. Chat scenes render the
/// view-only ``ScreenshotCanvas``; Connections pushes the real screen into a
/// stack, mirroring how it sits inside Settings.
struct ScreenshotSceneRoot: View {
    let scene: ScreenshotScene
    /// Header chat for chat scenes; created by the installer. The connections
    /// scene doesn't need one.
    let chat: Chat?
    /// Fixture agent's symbol, shown in the canvas headers.
    var agentEmoji: String?

    init(scene: ScreenshotScene, chat: Chat?, agentEmoji: String? = nil) {
        self.scene = scene
        self.chat = chat
        self.agentEmoji = agentEmoji
    }

    /// Anchor the UI tests wait for instead of matching on text, so a copy or
    /// locale change cannot break the captures.
    static let anchorIdentifier = "screenshot-scene"

    var body: some View {
        Group {
            switch scene {
            case .memory:
                ScreenshotCanvas(chat: chat, items: ScreenshotMemoryScene.items, emoji: agentEmoji)
            case .followUp:
                ScreenshotCanvas(
                    chat: chat,
                    items: ScreenshotFollowUpScene.items,
                    emoji: agentEmoji,
                    composerText: "Yes please."
                )
            case .onDevice:
                ScreenshotCanvas(
                    chat: chat,
                    items: ScreenshotOnDeviceScene.items,
                    emoji: agentEmoji
                )
            case .care:
                ScreenshotCanvas(chat: chat, items: ScreenshotCareScene.items, emoji: agentEmoji)
            case .asksFirst:
                ScreenshotCanvas(
                    chat: chat,
                    items: ScreenshotAsksFirstScene.items,
                    permissionRequest: ScreenshotAsksFirstScene.permissionRequest,
                    emoji: agentEmoji
                )
            case .connections:
                NavigationStack { ConnectionsView() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.anchorIdentifier)
    }
}

extension ScreenshotScene {
    /// Title for the header chat; only used when the installer stages the
    /// scene's header chat.
    var chatTitle: String? {
        switch self {
        case .memory: ScreenshotMemoryScene.chatTitle
        case .asksFirst: ScreenshotAsksFirstScene.chatTitle
        case .followUp: ScreenshotFollowUpScene.chatTitle
        case .onDevice: ScreenshotOnDeviceScene.chatTitle
        case .care: ScreenshotCareScene.chatTitle
        case .connections: nil
        }
    }
}
