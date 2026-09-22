import Factory
import Foundation
import UIKit
import UserNotifications
import WatchConnectivity

/// The phone's link to the watch: receives questions from the watch
/// companion.
///
/// `WCSession` launches the app in the background when the watch sends a
/// message, which is what lets a wrist tap ask a question with the phone
/// locked in a pocket. It only works if the app has been launched at least
/// once since install and the user has not force-quit it.
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
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
                    ], announcing: Localized.Watch.didntCatch)
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
                ], announcing: Localized.Watch.transcribeFailed)
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
    /// tool-using turn will outrun. The assertion buys the rest. When even
    /// that runs low, the turn is given up and a guidance message goes out
    /// before the app suspends — the question is already persisted to the
    /// watch chat, so the next message (wrist or phone) continues from it.
    /// A suspended turn never resumes on its own, so waiting is pointless.
    @MainActor
    private static func answer(question: String) async {
        var gaveUp = false
        let turn = Task {
            try await WatchTurnRunner.run(question: question, isAbandoned: { gaveUp })
        }
        let budget = BackgroundTaskGuard(onExpiring: {
            gaveUp = true
            turn.cancel()
            AppLogger.warning(
                "Watch turn outlived its background budget, giving up",
                category: .watch
            )
            // The expiration window must be spent on local queue operations
            // only: park the message in the transfer queue and mirror it by
            // notification. `sendMessage` needs the session to answer and
            // could linger past suspension, losing the message.
            WCSession.default.transferUserInfo([
                WatchMessage.actionKey: WatchMessage.answer,
                WatchMessage.errorKey: Localized.Watch.turnDelayed,
            ])
            notify(Localized.Watch.turnDelayed)
        })
        budget.begin()
        defer { budget.end() }

        do {
            let reply = try await turn.value
            AppLogger.info("Watch turn answered", category: .watch)
            send([
                WatchMessage.actionKey: WatchMessage.answer,
                WatchMessage.replyKey: reply,
            ], announcing: reply)
        } catch {
            // The give-up message already went out; a cancelled turn's error
            // is not a second, competing answer.
            guard !gaveUp else { return }
            AppLogger.error(
                "Watch turn failed: \(private: error.localizedDescription)", category: .watch
            )
            send([
                WatchMessage.actionKey: WatchMessage.answer,
                WatchMessage.errorKey: Localized.Watch.noReply,
            ], announcing: Localized.Watch.noReply)
        }
    }

    /// Announces an answer from the phone for queued deliveries: a phone
    /// notification mirrors to the wrist. See `WatchReplyRouter`.
    private static func notify(_ body: String) {
        guard shouldNotify(appState: UIApplication.shared.applicationState),
              !body.isEmpty
        else { return }
        let content = UNMutableNotificationContent()
        content.title = "Eigin"
        content.body = body
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

    /// Whether an answer's announcement warrants a notification banner.
    /// Skipped when the app is foreground-active: the user already has the
    /// app in front of them, and the answer lands in the chat and on the
    /// watch regardless.
    static func shouldNotify(appState: UIApplication.State) -> Bool {
        appState != .active
    }

    /// Pushes the answer to the watch — live while the watch app is reachable,
    /// else a queued transfer — and announces `body` from the phone only when
    /// the answer goes out queued. See `WatchReplyRouter`.
    private static func send(_ answer: [String: Any], announcing body: String) {
        let session = WCSession.default
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(answer, replyHandler: nil) { error in
                AppLogger.warning(
                    "Direct send failed, queueing: \(private: error.localizedDescription)",
                    category: .watch
                )
                session.transferUserInfo(answer)
                notify(body)
            }
        } else {
            // A queued transfer lands once the session activates, even when the
            // phone app is not running at send time.
            session.transferUserInfo(answer)
            notify(body)
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
