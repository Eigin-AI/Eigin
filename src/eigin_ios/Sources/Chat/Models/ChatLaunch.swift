import Foundation

/// How a chat opens beyond a plain read — one case per widget, shortcut and
/// Spotlight entry point.
///
/// Distinct from ``InteractionMode``, which is a conversation-level setting the
/// model is told about. This is a one-shot instruction to the view: arm the
/// mic, present the call sheet, open the camera.
enum ChatOpening: Hashable {
    case dictation
    case liveCall
    case camera

    /// The opening a route asks for, or `nil` for a plain new chat. Lives here
    /// rather than on ``EiginRoute``, which also compiles into the widget
    /// extension where the chat domain does not exist.
    init?(route: EiginRoute) {
        switch route {
        case .dictationChat: self = .dictation
        case .liveCallChat: self = .liveCall
        case .photoChat: self = .camera
        case .newChat, .openApp: return nil
        }
    }
}

/// A pushed chat navigation value: the chat to open plus how it should open.
///
/// Bare chat-row taps push these with nothing set; widget and shortcut
/// launches push one with the opening preset. Carrying it on the value itself —
/// instead of persisted flags read somewhere later — means an action can never
/// fire in the wrong conversation.
struct ChatLaunch: Hashable {
    let chatID: UUID
    var opening: ChatOpening?
}
