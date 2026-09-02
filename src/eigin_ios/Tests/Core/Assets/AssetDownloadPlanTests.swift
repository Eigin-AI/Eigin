@testable import Eigin
import Foundation
import Testing

/// Manifest → parts, and the sidecar round-trip.
struct AssetDownloadPlanTests {
    private let chunking = AssetDownloadPlan.Chunking(threshold: 100, size: 40)

    private func manifest(_ sizes: [Int64]) -> AssetManifest {
        AssetManifest(
            id: "asset", version: "v1",
            files: sizes.enumerated().map { index, size in
                .init(path: "f\(index)", size: size, sha256: "", url: "https://x/f\(index)")
            }
        )
    }

    @Test func smallFilesAreOneWholePart() {
        let plan = AssetDownloadPlan.make(
            assetID: "a",
            manifest: manifest([10, 99]),
            chunking: chunking
        )
        #expect(plan.parts.count == 2)
        #expect(plan.parts.allSatisfy { $0.isWhole })
        #expect(plan.isChunked(fileIndex: 0) == false)
    }

    @Test func largeFilesSplitIntoRangesWithShortTail() {
        let plan = AssetDownloadPlan.make(
            assetID: "a",
            manifest: manifest([100]),
            chunking: chunking
        )
        #expect(plan.parts.map(\.offset) == [0, 40, 80])
        #expect(plan.parts.map(\.length) == [40, 40, 20])
        #expect(plan.parts.last?.end == 99)
        #expect(plan.parts.allSatisfy { !$0.isWhole })
        #expect(plan.isChunked(fileIndex: 0))
    }

    @Test func bigFilesComeFirst() {
        let plan = AssetDownloadPlan.make(
            assetID: "a",
            manifest: manifest([5, 120, 50]),
            chunking: chunking
        )
        #expect(plan.parts.map(\.fileIndex) == [1, 1, 1, 2, 0])
    }

    @Test func progressAccounting() {
        var plan = AssetDownloadPlan.make(
            assetID: "a",
            manifest: manifest([100, 7]),
            chunking: chunking
        )
        #expect(plan.totalBytes == 107)
        plan.completed.insert(plan.parts[0])
        plan.completed.insert(plan.parts[3])
        #expect(plan.completedBytes == 47)
        #expect(!plan.isComplete)
        plan.reset(fileIndex: 0)
        #expect(plan.completedBytes == 7)
    }

    @Test func refreshKeepsProgressAndSwapsURLs() {
        var plan = AssetDownloadPlan.make(
            assetID: "a",
            manifest: manifest([10]),
            chunking: chunking
        )
        plan.completed.insert(plan.parts[0])
        var fresh = manifest([10])
        fresh = AssetManifest(id: fresh.id, version: fresh.version, files: [
            .init(path: "f0", size: 10, sha256: "", url: "https://x/f0?sig=new"),
        ])
        let refreshed = plan.refreshingURLs(from: fresh)
        #expect(refreshed.files[0].url == "https://x/f0?sig=new")
        #expect(refreshed.completed == plan.completed)
    }

    @Test func sidecarRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var plan = AssetDownloadPlan.make(
            assetID: "a",
            manifest: manifest([100]),
            chunking: chunking
        )
        plan.completed.insert(plan.parts[1])

        #expect(AssetDownloadPlan.load(from: dir) == nil)
        plan.save(in: dir)
        let loaded = try #require(AssetDownloadPlan.load(from: dir))
        #expect(loaded.version == "v1")
        #expect(loaded.parts == plan.parts)
        #expect(loaded.completed == plan.completed)
        #expect(loaded.chunking == chunking)

        AssetDownloadPlan.remove(from: dir)
        #expect(AssetDownloadPlan.load(from: dir) == nil)
    }
}
