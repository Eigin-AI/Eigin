@testable import Eigin
import Testing

/// Verifies storage gating in ``GemmaModelManager``.
@MainActor
@Suite("GemmaModelManager")
struct GemmaModelManagerTests {
    /// Fake ``DiskSpaceService`` for deterministic storage tests.
    struct FakeDiskSpaceService: DiskSpaceService {
        var bytes: Int64?

        func availableBytes() -> Int64? {
            bytes
        }
    }

    // MARK: – Storage gating

    @Test func downloadTransitionsToFailedWhenStorageIsLow() async {
        let manager = GemmaModelManager(diskSpaceService: FakeDiskSpaceService(bytes: 1))
        await manager.download()

        if case .failed(let message) = manager.state {
            #expect(message.contains("GB"))
        } else {
            Issue.record("Expected .failed state, got \(manager.state)")
        }
    }

    @Test func downloadStartsWhenStorageIsAdequate() {
        let required = GemmaModelManager.minimumRequiredFreeSpaceBytes(
            for: GemmaModelDownloader.ModelInfo.default
        )

        let manager = GemmaModelManager(
            diskSpaceService: FakeDiskSpaceService(bytes: required + 1)
        )

        #expect(manager.hasSufficientStorage())
    }
}
