@preconcurrency import AVFoundation

/// Watches the audio route and interruption state during a live call and
/// signals when the active audio graph needs rebuilding.
///
/// A Bluetooth connect/disconnect, a headphone plug, or the end of an
/// interruption can leave the input or output engine bound to a stale device.
/// This coordinator observes those events on the main actor, debounces bursts
/// (getting into a car fires many at once), and fires ``onRecover`` once things
/// settle — leaving the actual graph rebuild to whichever service is active.
@MainActor
final class AudioRouteCoordinator {
    /// Called, debounced, when the active audio graph should be rebuilt.
    var onRecover: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration
    private let notificationCenter: NotificationCenter

    init(
        debounceInterval: Duration = .milliseconds(350),
        notificationCenter: NotificationCenter = .default
    ) {
        self.debounceInterval = debounceInterval
        self.notificationCenter = notificationCenter
    }

    /// Begin observing route and interruption changes.
    func start() {
        stop()
        let route = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            let reason = Self.routeChangeReason(notification)
            MainActor.assumeIsolated { self?.handleRouteChange(reason) }
        }
        let interruption = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            let type = Self.interruptionType(notification)
            MainActor.assumeIsolated { self?.handleInterruption(type) }
        }
        observers = [route, interruption]
    }

    /// Stop observing and cancel any pending recovery.
    func stop() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Handlers

    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason?) {
        // Only act when a device appears or disappears — this covers every
        // Bluetooth/headphone/car switch, including swaps between two devices
        // with the same audio format. Deliberately ignore `.override` (which we
        // trigger ourselves via speaker routing) to avoid a feedback loop.
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            scheduleRecover()
        default:
            break
        }
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?) {
        // Rebuild once an interruption ends and the session is ours again.
        if type == .ended { scheduleRecover() }
    }

    /// Coalesce a burst of route changes into a single recovery.
    private func scheduleRecover() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            onRecover?()
        }
    }

    // MARK: - Parsing

    private nonisolated static func routeChangeReason(
        _ notification: Notification
    ) -> AVAudioSession.RouteChangeReason? {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        else { return nil }
        return AVAudioSession.RouteChangeReason(rawValue: raw)
    }

    private nonisolated static func interruptionType(
        _ notification: Notification
    ) -> AVAudioSession.InterruptionType? {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        else { return nil }
        return AVAudioSession.InterruptionType(rawValue: raw)
    }
}
