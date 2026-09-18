import Foundation
import Observation
import UserNotifications
import WatchConnectivity

/// Sends a dictated question to the phone and learns when the turn finished.
/// The watch's link to the phone.
///
/// `sendMessage` launches the phone app in the background when it is not
/// running, which is what lets a pocketed, locked phone answer. It fails when
/// the user has force-quit the app — surfaced rather than left silent.
@Observable
@MainActor
final class PhoneLink: NSObject, WCSessionDelegate {
    /// The turn is done: the reply arrives here and on the wrist as a
    /// notification.
    var onAnswer: ((String, String?) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var isActive: Bool {
        WCSession.default.activationState == .activated
    }

    /// Sends a recorded question: wake the phone, then transfer the audio.
    /// `onError` fires when the wake fails — most often the phone app was
    /// force-quit or is out of range.
    func send(url: URL, onError: @escaping (String) -> Void) {
        guard isActive else {
            onError(Localized.Watch.cantReachPhone)
            return
        }

        // Wake the phone first: a file transfer alone is delivered when the
        // app next runs, so on its own it would sit in the queue until then.
        // The message launches it; the file follows. The transfer goes out
        // right after the wake, not inside its reply handler — a transfer
        // queued from within the handler never delivers.
        WCSession.default.sendMessage(
            [WatchMessage.actionKey: WatchMessage.audioIncoming],
            replyHandler: { _ in },
            errorHandler: { _ in
                Task { @MainActor in
                    onError(Localized.Watch.cantReachPhone)
                }
            }
        )
        WCSession.default.transferFile(url, metadata: [
            WatchMessage.actionKey: WatchMessage.ask,
        ])
    }

    /// Pulls the Sendable pieces out of the answer before hopping to the actor
    /// — `[String: Any]` cannot cross the boundary.
    private nonisolated func handle(
        _ answer: [String: Any], via transport: WatchReplyRouter.Transport
    ) {
        guard answer[WatchMessage.actionKey] as? String == WatchMessage.answer else { return }
        let reply = answer[WatchMessage.replyKey] as? String ?? ""
        let error = answer[WatchMessage.errorKey] as? String
        Task { @MainActor [weak self] in
            // One announcement per reply — see `WatchReplyRouter`.
            if WatchReplyRouter.announcer(for: transport) == .watch {
                self?.notify(reply: reply, error: error)
            }
            self?.onAnswer?(reply, error)
        }
    }

    /// The answer is the wrist's notification for live deliveries: posted
    /// whether or not the app is frontmost — in the foreground it stays quiet
    /// while the haptic and the screen carry it, in the background the banner
    /// delivers the words.
    @MainActor private func notify(reply: String, error: String?) {
        let body = error ?? reply
        guard !body.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "Eigin"
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil
            )
        )
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message, via: .live)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo, via: .queued)
    }
}
