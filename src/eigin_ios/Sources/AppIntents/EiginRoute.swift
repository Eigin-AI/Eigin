import AppIntents
import Foundation

/// The ways a chat can be opened from outside the app's normal navigation.
///
/// Backs the interactive widget and App Shortcuts, and encodes to the custom
/// URL scheme (`eigin://new-chat`) so a widget-extension process can hand the
/// request to the app it is embedded in.
enum EiginRoute: String, CaseIterable {
    /// Open the app at the chat list, nothing pre-armed.
    case openApp = "open"
    /// Start a fresh chat with the keyboard ready.
    case newChat = "new-chat"
    /// Start a fresh chat with dictation already running.
    case dictationChat = "dictation-chat"
    /// Start a fresh chat dropped straight into a live call.
    case liveCallChat = "live-call-chat"
    /// Start a fresh chat with the camera ready to attach a photo.
    case photoChat = "photo-chat"

    static let scheme = "eigin"

    /// The URL the widget uses to hand this route off to the app.
    var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    /// Reconstructs a route from a URL; only accepts our scheme with a known
    /// route token, ignoring anything else a caller might have sent.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        guard let token = Self.token(from: url),
              let route = Self(rawValue: token) else { return nil }
        self = route
    }

    private static func token(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if !host.isEmpty { return host }
        // eigin://new-chat can surface as host or path depending on producer.
        let path = url.path(percentEncoded: false)
        guard !path.isEmpty else { return nil }
        return String(path.drop(while: { $0 == "/" })).lowercased()
    }
}
