@testable import Eigin
import Foundation
import Testing

/// Verifies device requirement gating in ``GemmaModelManager``.
@MainActor
@Suite("GemmaModelManager")
struct GemmaModelManagerTests {
    /// Fake ``DeviceInfoService`` for deterministic capability tests.
    struct FakeDeviceInfoService: DeviceInfoService {
        var diskBytes: Int64?
        var ramBytes: UInt64
        var identifier: String

        init(
            diskBytes: Int64? = nil,
            ramBytes: UInt64 = 8 * 1_073_741_824,
            identifier: String = "iPhone16,1"
        ) {
            self.diskBytes = diskBytes
            self.ramBytes = ramBytes
            self.identifier = identifier
        }

        func freeDiskSpaceBytes() -> Int64? {
            diskBytes
        }

        func physicalMemoryBytes() -> UInt64 {
            ramBytes
        }

        func deviceIdentifier() -> String {
            identifier
        }

        func systemVersion() -> String {
            "1.0"
        }

        func appBuildVersion() -> String {
            "test-build"
        }

        func appName() -> String {
            "Eigin"
        }

        func appVersion() -> String {
            "1.0"
        }
    }

    // MARK: – RAM gating

    @Test func downloadTransitionsToFailedWhenRAMIsLow() async {
        let manager = GemmaModelManager(
            deviceInfo: FakeDeviceInfoService(
                diskBytes: .max,
                ramBytes: 4 * 1_073_741_824
            )
        )
        await manager.download()

        if case .failed(let message) = manager.state {
            #expect(message.contains("iPhone 15"))
        } else {
            Issue.record("Expected .failed state, got \(manager.state)")
        }
    }

    @Test func hasRequiredRAMReturnsFalseForFourGigabytes() {
        let manager = GemmaModelManager(
            deviceInfo: FakeDeviceInfoService(ramBytes: 4 * 1_073_741_824)
        )
        #expect(!manager.hasRequiredRAM())
    }

    @Test func hasRequiredRAMReturnsTrueForSixGigabytes() {
        let manager = GemmaModelManager(
            deviceInfo: FakeDeviceInfoService(ramBytes: 6 * 1_073_741_824)
        )
        #expect(manager.hasRequiredRAM())
    }

    @Test func insufficientResourcesDetailIsJSONWithMemoryFields() throws {
        let manager = GemmaModelManager(
            deviceInfo: FakeDeviceInfoService(ramBytes: 4 * 1_073_741_824)
        )

        let detail = manager.insufficientResourcesDetail()
        let data = try #require(detail.data(using: .utf8))
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let errorObj = try #require(root["error"] as? [String: Any])

        #expect(errorObj["type"] as? String == "insufficient_memory")
        #expect(errorObj["device_memory_gb"] as? String == "4.0")
        #expect(errorObj["required_memory_gb"] as? String == "5.0")
        #expect(errorObj["message"] as? String != nil)
    }

    // MARK: – Storage gating

    @Test func downloadTransitionsToFailedWhenStorageIsLow() async {
        let manager = GemmaModelManager(
            deviceInfo: FakeDeviceInfoService(diskBytes: 1)
        )
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
            deviceInfo: FakeDeviceInfoService(diskBytes: required + 1)
        )

        #expect(manager.hasRequiredDiskSpace())
    }
}
