@preconcurrency import AVFoundation
@testable import Eigin
import Testing

@Suite("AudioRouteCoordinator")
@MainActor
struct AudioRouteCoordinatorTests {
    private final class Counter { var value = 0 }

    private static func makeCoordinator(
        center: NotificationCenter
    ) -> (AudioRouteCoordinator, Counter) {
        let counter = Counter()
        let coordinator = AudioRouteCoordinator(
            debounceInterval: .milliseconds(20), notificationCenter: center
        )
        coordinator.onRecover = { counter.value += 1 }
        coordinator.start()
        return (coordinator, counter)
    }

    private static func postRouteChange(
        _ center: NotificationCenter, reason: AVAudioSession.RouteChangeReason
    ) {
        center.post(
            name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
    }

    private static func postInterruption(
        _ center: NotificationCenter, type: AVAudioSession.InterruptionType
    ) {
        center.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue]
        )
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(80))
    }

    @Test func recoversWhenADeviceAppears() async {
        let center = NotificationCenter()
        let (coordinator, counter) = Self.makeCoordinator(center: center)
        defer { coordinator.stop() }

        Self.postRouteChange(center, reason: .newDeviceAvailable)
        await Self.settle()

        #expect(counter.value == 1)
    }

    @Test func recoversWhenADeviceDisappears() async {
        let center = NotificationCenter()
        let (coordinator, counter) = Self.makeCoordinator(center: center)
        defer { coordinator.stop() }

        Self.postRouteChange(center, reason: .oldDeviceUnavailable)
        await Self.settle()

        #expect(counter.value == 1)
    }

    @Test func coalescesABurstIntoASingleRecovery() async {
        let center = NotificationCenter()
        let (coordinator, counter) = Self.makeCoordinator(center: center)
        defer { coordinator.stop() }

        // A car handover fires several route changes in quick succession.
        Self.postRouteChange(center, reason: .oldDeviceUnavailable)
        Self.postRouteChange(center, reason: .newDeviceAvailable)
        Self.postRouteChange(center, reason: .newDeviceAvailable)
        await Self.settle()

        #expect(counter.value == 1)
    }

    @Test func ignoresNonDeviceRouteChanges() async {
        let center = NotificationCenter()
        let (coordinator, counter) = Self.makeCoordinator(center: center)
        defer { coordinator.stop() }

        // We trigger `.override` ourselves via speaker routing — acting on it
        // would loop. `.categoryChange` is routine and shouldn't rebuild.
        Self.postRouteChange(center, reason: .override)
        Self.postRouteChange(center, reason: .categoryChange)
        await Self.settle()

        #expect(counter.value == 0)
    }

    @Test func recoversWhenAnInterruptionEnds() async {
        let center = NotificationCenter()
        let (coordinator, counter) = Self.makeCoordinator(center: center)
        defer { coordinator.stop() }

        Self.postInterruption(center, type: .ended)
        await Self.settle()

        #expect(counter.value == 1)
    }

    @Test func ignoresInterruptionBegan() async {
        let center = NotificationCenter()
        let (coordinator, counter) = Self.makeCoordinator(center: center)
        defer { coordinator.stop() }

        Self.postInterruption(center, type: .began)
        await Self.settle()

        #expect(counter.value == 0)
    }

    @Test func stopHaltsFurtherRecovery() async {
        let center = NotificationCenter()
        let (coordinator, counter) = Self.makeCoordinator(center: center)

        coordinator.stop()
        Self.postRouteChange(center, reason: .newDeviceAvailable)
        await Self.settle()

        #expect(counter.value == 0)
    }
}
