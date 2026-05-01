@preconcurrency import AVFoundation
@preconcurrency import CallKit

/// Manages a CallKit VoIP call so the live call session stays alive
/// in the background and shows native call UI on the lock screen.
///
/// Singleton — the ``CXProvider`` must be registered with the telephony
/// system before the first call. Creating it once at first access ensures
/// the provider is ready by the time the user taps "call".
final class CallManager: NSObject, CXProviderDelegate, @unchecked Sendable {
    static let shared = CallManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private(set) var activeCallUUID: UUID?

    // MARK: - Callbacks (set per-session by LiveCallService)

    var onAudioActivated: (() -> Void)?
    var onAudioDeactivated: (() -> Void)?
    var onCallEnded: (() -> Void)?
    var onMuteChanged: ((Bool) -> Void)?

    // MARK: - Init

    override private init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.includesCallsInRecents = false
        config.supportedHandleTypes = [.generic]
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: - Public API

    func startCall(handle: String) {
        let uuid = UUID()
        activeCallUUID = uuid
        let cxHandle = CXHandle(type: .generic, value: handle)
        let action = CXStartCallAction(call: uuid, handle: cxHandle)
        action.isVideo = false
        callController.request(CXTransaction(action: action)) { error in
            if let error { AppLogger.error(
                "Start call failed: \(private: error.localizedDescription)",
                category: .livecall
            ) }
        }
    }

    func endCall() {
        guard let uuid = activeCallUUID else { return }
        let action = CXEndCallAction(call: uuid)
        callController.request(CXTransaction(action: action)) { error in
            if let error { AppLogger.error(
                "End call failed: \(private: error.localizedDescription)",
                category: .livecall
            ) }
        }
    }

    /// Clear per-session callbacks so nothing fires after the session ends.
    func clearCallbacks() {
        onAudioActivated = nil
        onAudioDeactivated = nil
        onCallEnded = nil
        onMuteChanged = nil
    }

    // MARK: - CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        AppLogger.warning("Provider did reset", category: .livecall)
        activeCallUUID = nil
        Task { @MainActor in onCallEnded?() }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // Configure audio session category before CallKit activates it.
        // Use .default mode (not .voiceChat) for full speaker volume —
        // .voiceChat applies phone-call-level volume limiting. Our
        // Live call is turn-based so we don't need echo cancellation.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )

        // Report full call metadata so the system shows the complete call UI
        // (name, duration timer, mute/speaker/end buttons).
        let update = CXCallUpdate()
        update.remoteHandle = action.handle
        update.localizedCallerName = action.handle.value
        update.hasVideo = false
        update.supportsDTMF = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        provider.reportCall(with: action.callUUID, updated: update)

        // Report "connecting" — the system needs to see this state before
        // we transition to "connected" in didActivate.
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        activeCallUUID = nil
        Task { @MainActor in onCallEnded?() }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in onMuteChanged?(action.isMuted) }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        AppLogger.info("Audio session activated", category: .livecall)
        // Transition to "connected" now that the audio session is live.
        // This triggers the system to show the full call UI with duration timer.
        if let uuid = activeCallUUID {
            provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        }

        Task { @MainActor in onAudioActivated?() }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        AppLogger.info("Audio session deactivated", category: .livecall)
        Task { @MainActor in onAudioDeactivated?() }
    }
}
