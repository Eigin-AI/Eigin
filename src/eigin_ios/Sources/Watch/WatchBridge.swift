import Factory
import Foundation
import UIKit
import UserNotifications
import WatchConnectivity

/// Receives questions from the watch companion.
///
/// `WCSession` launches the app in the background when the watch sends a
/// message, which is what lets a wrist tap ask a question with the phone
/// locked in a pocket. It only works if the app has been launched at least
/// once since install and the user has not force-quit it.
final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    override init() {
        super.init()
    }

    /// Activates the session. Safe to call on devices with no paired watch.
    func activate() {
        guard WCSession.isSupported() else {
            AppLogger.info("WatchConnectivity unsupported", category: .watch)
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Receives a question recorded on the watch, transcribes it here, and
    /// answers it. The watch has no speech framework, and transcribing on the
    /// phone also applies the user's configured language and vocabulary.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[WatchMessage.actionKey] as? String == WatchMessage.ask else {
            return
        }
        // The file is deleted as soon as this returns, so take a copy first.
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-\(UUID().uuidString).m4a")
        try? FileManager.default.copyItem(at: file.fileURL, to: copy)

        AppLogger.info("Watch sent a recording", category: .watch)
        Task { @MainActor in
            // The answer takes its own assertion from here.
            Self.releaseTransferHold()
            defer { try? FileManager.default.removeItem(at: copy) }
            let language = Container.shared.languageManager().currentLanguage
            do {
                let question = try await AudioFileTranscriber.transcribe(
                    url: copy,
                    locale: Locale(identifier: language.speechLocaleIdentifier)
                )
                guard !question.isEmpty else {
                    AppLogger.info("Watch recording had no speech", category: .watch)
                    Self.send([
                        WatchMessage.actionKey: WatchMessage.answer,
                        WatchMessage.errorKey: Localized.Watch.didntCatch,
                    ])
                    return
                }
                await Self.answer(question: question)
            } catch {
                AppLogger.error(
                    "Watch transcription failed: \(private: error.localizedDescription)",
                    category: .watch
                )
                Self.send([
                    WatchMessage.actionKey: WatchMessage.answer,
                    WatchMessage.errorKey: Localized.Watch.transcribeFailed,
                ])
            }
        }
    }

    // MARK: - Staying awake for a transfer

    /// The assertion held between the wake message and the file arriving.
    @MainActor private static var transferTask = UIBackgroundTaskIdentifier.invalid
    /// Long enough for a recording to cross, short enough not to squat on the
    /// app's background time if the transfer never comes.
    private static let transferWindow: TimeInterval = 30

    @MainActor
    private static func holdAwakeForTransfer() {
        releaseTransferHold()
        transferTask = UIApplication.shared.beginBackgroundTask(withName: "WatchAudio") {
            releaseTransferHold()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(transferWindow))
            releaseTransferHold()
        }
    }

    @MainActor
    private static func releaseTransferHold() {
        guard transferTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(transferTask)
        transferTask = .invalid
    }

    // MARK: - Answering

    /// Runs the turn under a background assertion and delivers the result.
    ///
    /// A WatchConnectivity wake gives only a few seconds by default, which a
    /// tool-using turn will outrun. The assertion buys the rest.
    @MainActor
    private static func answer(question: String) async {
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "WatchTurn") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        defer {
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }

        do {
            let reply = try await WatchTurnRunner.run(question: question)
            AppLogger.info("Watch turn answered", category: .watch)
            send([
                WatchMessage.actionKey: WatchMessage.answer,
                WatchMessage.replyKey: reply,
            ])
            notify(reply)
        } catch {
            AppLogger.error(
                "Watch turn failed: \(private: error.localizedDescription)", category: .watch
            )
            send([
                WatchMessage.actionKey: WatchMessage.answer,
                WatchMessage.errorKey: Localized.Watch.noReply,
            ])
        }
    }

    /// Delivers the reply as a notification, so it reaches the wrist even
    /// though the watch app is no longer running. A phone notification mirrors
    /// to the wrist, which the suspended watch app cannot do for itself.
    private static func notify(_ reply: String) {
        guard !reply.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "Eigin"
        content.body = reply
        content.sound = .default
        // Tapping on the phone opens the watch chat, so the conversation is
        // there to continue.
        if let chatID = WatchChat.storedID() {
            content.userInfo["chatID"] = chatID.uuidString
        }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil
            )
        )
    }

    /// Pushes a payload to the watch, falling back to a queued transfer when
    /// the watch app is no longer in the foreground.
    private static func send(_ payload: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                AppLogger.warning(
                    "Direct send failed, queueing: \(private: error.localizedDescription)",
                    category: .watch
                )
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            AppLogger.error(
                "Watch session activation failed: \(private: error.localizedDescription)",
                category: .watch
            )
            return
        }
        AppLogger.info(
            "Watch session active (paired: \(public: session.isPaired))", category: .watch
        )
    }

    /// Required on iOS so the session can be handed to a newly paired watch.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        switch message[WatchMessage.actionKey] as? String {
        case WatchMessage.audioIncoming:
            // Woken ahead of a recording. Hold the app awake so the transfer
            // lands now rather than whenever the user next opens the app.
            replyHandler([WatchMessage.statusKey: WatchMessage.woke])
            AppLogger.info("Watch is sending a recording", category: .watch)
            Task { @MainActor in Self.holdAwakeForTransfer() }
        default:
            // The question itself never arrives as a message — it rides the
            // file transfer's metadata, handled in `didReceive file`.
            replyHandler([WatchMessage.statusKey: WatchMessage.unknownAction])
        }
    }
}
