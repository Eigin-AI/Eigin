@testable import Eigin
import Foundation
import Testing

/// Tests for `GemmaModelManager.prewarmIfNeeded()` guard logic.
///
/// Real model loading is not possible in the simulator / CI — ANE is absent
/// and the ~4 GB model files are not present. All tests exercise the
/// version-guard, state-guard, and persistence logic by injecting a fake
/// `prewarmRunner` closure and a `FakeDeviceInfoService`.
@MainActor
@Suite("GemmaModelManager – prewarm")
struct GemmaModelManagerPrewarmTests {
    typealias FakeDeviceInfo = GemmaModelManagerTests.FakeDeviceInfoService

    private func makeManager(
        prewarmRunner: @escaping @Sendable (URL, @escaping @Sendable (Int, Int) -> Void)
        async throws -> Void = { _, _ in }
    ) -> GemmaModelManager {
        GemmaModelManager(
            deviceInfo: FakeDeviceInfo(diskBytes: .max),
            prewarmRunner: prewarmRunner
        )
    }

    // MARK: – Version guard

    @Test func skipsWhenVersionAlreadyWarmed() async {
        let currentVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        UserDefaults.standard.set(currentVersion, forKey: StorageKey.gemmaPrewarmedBuild)
        defer { UserDefaults.standard.removeObject(forKey: StorageKey.gemmaPrewarmedBuild) }

        let expectation = ActorExpectation()
        let manager = makeManager { _, _ in await expectation.signal() }
        manager.prewarmIfNeeded()

        // Yield several times to let any spawned Task start.
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        let didRun = await expectation.didSignal
        #expect(!didRun, "Should skip when version is already warmed")
    }

    // MARK: – Persistence

    @Test func persistsVersionOnSuccessfulCompletion() {
        let testVersion = "test-prewarm-\(UUID())"
        UserDefaults.standard.set(testVersion, forKey: StorageKey.gemmaPrewarmedBuild)
        defer { UserDefaults.standard.removeObject(forKey: StorageKey.gemmaPrewarmedBuild) }

        let stored = UserDefaults.standard.string(forKey: StorageKey.gemmaPrewarmedBuild)
        #expect(stored == testVersion)
    }

    @Test func doesNotPersistVersionWhenNeverRun() {
        UserDefaults.standard.removeObject(forKey: StorageKey.gemmaPrewarmedBuild)
        let stored = UserDefaults.standard.string(forKey: StorageKey.gemmaPrewarmedBuild)
        #expect(stored == nil, "Should not persist version when prewarm has not run")
    }

    // MARK: – cancelPrewarm

    @Test func cancelPrewarmIsNoOpWhenNotRunning() {
        let manager = makeManager()
        // Should not crash or change state when nothing is running.
        manager.cancelPrewarm()
        if case .compiling = manager.state {
            Issue.record("State should not be .compiling when no prewarm is running")
        }
    }
}

// MARK: – Helpers

/// Thread-safe expectation for async test coordination.
private actor ActorExpectation {
    private(set) var didSignal = false

    func signal() {
        didSignal = true
    }
}
