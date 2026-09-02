import Crypto
@testable import Eigin
import Foundation
import Testing

/// End-to-end downloads through a `URLSession` backed by `FakeURLProtocol`:
/// concurrent files, byte-range assembly, verification, failure, cancel.
@MainActor
@Suite(.serialized)
struct AssetDownloaderTests {
    private let chunking = AssetDownloadPlan.Chunking(threshold: 1000, size: 400)

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func bytes(_ count: Int, seed: UInt8) -> Data {
        Data((0 ..< count).map { UInt8(truncatingIfNeeded: $0) ^ seed })
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
    }

    /// Stub every file and return a manifest pointing at unique URLs.
    private func stub(
        _ files: [(path: String, data: Data, sha: String?)],
        version: String = "v1",
        status: Int = 200
    ) -> AssetManifest {
        let host = "https://assets.test/\(UUID().uuidString)"
        return AssetManifest(id: "asset", version: version, files: files.map { file in
            let url = "\(host)/\(file.path)"
            FakeURLProtocol.stubResponse(for: url, data: file.data, statusCode: status)
            return .init(
                path: file.path, size: Int64(file.data.count),
                sha256: file.sha ?? sha256(file.data), url: url
            )
        })
    }

    private func makeDownloader(
        manifest: @escaping @Sendable (String) async throws -> AssetManifest
    ) -> AssetDownloader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeURLProtocol.self]
        let defaults = UserDefaults(suiteName: "AssetDownloaderTests-\(UUID().uuidString)")!
        return AssetDownloader(
            configuration: config,
            manifest: manifest,
            registry: AssetDownloadRegistry(defaults: defaults, key: "inProgress"),
            chunking: chunking
        )
    }

    // MARK: - Tests

    @Test func downloadsManyFilesVerifiesAndWritesMarker() async throws {
        let a = bytes(300, seed: 1), b = bytes(50, seed: 2), c = bytes(700, seed: 3)
        let manifest = stub([("a.bin", a, nil), ("sub/b.bin", b, nil), ("c.bin", c, nil)])
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let downloader = makeDownloader { _ in manifest }
        try await downloader.download(.init(assetID: "asset", directory: dir))

        #expect(try Data(contentsOf: dir.appendingPathComponent("a.bin")) == a)
        #expect(try Data(contentsOf: dir.appendingPathComponent("sub/b.bin")) == b)
        #expect(try Data(contentsOf: dir.appendingPathComponent("c.bin")) == c)
        #expect(ModelAssetService.installedVersion(id: "asset", in: dir) == "v1")
        #expect(AssetDownloadPlan.load(from: dir) == nil)
        #expect(downloader.progress["asset"] == nil)
        #expect(!downloader.isDownloading(assetID: "asset"))
    }

    @Test func largeFileIsFetchedAsRangesAndReassembled() async throws {
        let big = bytes(1000, seed: 9)
        let manifest = stub([("big.bin", big, nil)])
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let downloader = makeDownloader { _ in manifest }
        try await downloader.download(.init(assetID: "asset", directory: dir))

        #expect(try Data(contentsOf: dir.appendingPathComponent("big.bin")) == big)
        let ranges = FakeURLProtocol.requestedRanges(for: manifest.files[0].url).sorted()
        #expect(ranges == ["bytes=0-399", "bytes=400-799", "bytes=800-999"])
    }

    @Test func mapsManifestPathsToLocalPaths() async throws {
        let data = bytes(20, seed: 4)
        let manifest = stub([("Pkg.mlpackage/Data/weights", data, nil)])
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let downloader = makeDownloader { _ in manifest }
        try await downloader.download(.init(assetID: "asset", directory: dir) { path in
            path.replacingOccurrences(of: "Pkg.mlpackage/", with: "_uncompiled/Pkg/")
        })

        #expect(try Data(contentsOf: dir.appendingPathComponent("_uncompiled/Pkg/Data/weights")) ==
            data)
    }

    @Test func httpErrorFailsWithStatus() async throws {
        let manifest = stub([("x.bin", Data("denied".utf8), nil)], status: 403)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let downloader = makeDownloader { _ in manifest }
        await #expect(throws: ModelAssetError.self) {
            try await downloader.download(.init(assetID: "asset", directory: dir))
        }
        #expect(ModelAssetService.installedVersion(in: dir) == nil)
        #expect(!downloader.isDownloading(assetID: "asset"))
    }

    @Test func checksumMismatchRemovesFileAndFails() async throws {
        let manifest = stub([("x.bin", bytes(30, seed: 5), String(repeating: "0", count: 64))])
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let downloader = makeDownloader { _ in manifest }
        await #expect(throws: ModelAssetError.self) {
            try await downloader.download(.init(assetID: "asset", directory: dir))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("x.bin").path))
        #expect(ModelAssetService.installedVersion(in: dir) == nil)
    }

    @Test func manifestFailureSurfacesToCaller() async throws {
        struct Offline: Error {}
        let dir = tempDir()
        let downloader = makeDownloader { _ in throw Offline() }
        await #expect(throws: Offline.self) {
            try await downloader.download(.init(assetID: "asset", directory: dir))
        }
        #expect(!downloader.isDownloading(assetID: "asset"))
    }

    @Test func cancelRemovesPartialFilesAndThrows() async throws {
        let manifest = stub([("x.bin", bytes(500, seed: 6), nil)])
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Hold the manifest fetch so the job is queued when we cancel.
        let gate = AsyncStream<Void>.makeStream()
        let downloader = makeDownloader { _ in
            for await _ in gate.stream {
                break
            }
            return manifest
        }

        let task = Task { try await downloader.download(.init(assetID: "asset", directory: dir)) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(downloader.isDownloading(assetID: "asset"))
        downloader.cancel(assetID: "asset")
        gate.continuation.yield()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        #expect(!downloader.isDownloading(assetID: "asset"))
    }

    @Test func cancelWithTasksInFlightDrainsThenRemovesDirectory() async throws {
        let manifest = stub([("slow.bin", bytes(1000, seed: 11), nil)])
        FakeURLProtocol.stubDelay(for: manifest.files[0].url, seconds: 0.5)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let downloader = makeDownloader { _ in manifest }

        let task = Task { try await downloader.download(.init(assetID: "asset", directory: dir)) }
        try await Task.sleep(for: .milliseconds(150))
        // Range tasks are running and the file is preallocated.
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("slow.bin").path))
        downloader.cancel(assetID: "asset")

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        #expect(!downloader.isDownloading(assetID: "asset"))
        #expect(downloader.progress["asset"] == nil)
    }

    @Test func secondCallerJoinsInFlightJob() async throws {
        let manifest = stub([("x.bin", bytes(100, seed: 7), nil)])
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let downloader = makeDownloader { _ in manifest }

        async let first: Void = downloader.download(.init(assetID: "asset", directory: dir))
        async let second: Void = downloader.download(.init(assetID: "asset", directory: dir))
        _ = try await (first, second)
        #expect(ModelAssetService.installedVersion(in: dir) == "v1")
    }

    @Test func retryAfterFailureResumesCompletedParts() async throws {
        // Two files: one that succeeds, one whose URL 500s on the first attempt.
        let good = bytes(1000, seed: 8), bad = bytes(60, seed: 10)
        let goodOnly = stub([("good.bin", good, nil)])
        let badURL = "https://assets.test/\(UUID().uuidString)/bad.bin"
        FakeURLProtocol.enqueueResponse(for: badURL, data: Data("boom".utf8), statusCode: 500)
        FakeURLProtocol.stubResponse(for: badURL, data: bad, statusCode: 200)
        let manifest = AssetManifest(id: "asset", version: "v1", files: goodOnly.files + [
            .init(path: "bad.bin", size: Int64(bad.count), sha256: sha256(bad), url: badURL),
        ])
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let downloader = makeDownloader { _ in manifest }

        await #expect(throws: ModelAssetError.self) {
            try await downloader.download(.init(assetID: "asset", directory: dir))
        }
        // Partial progress survives the failure.
        let sidecar = try #require(AssetDownloadPlan.load(from: dir))
        #expect(!sidecar.completed.isEmpty)
        let rangesBefore = FakeURLProtocol.requestedRanges(for: manifest.files[0].url).count

        try await downloader.download(.init(assetID: "asset", directory: dir))

        #expect(try Data(contentsOf: dir.appendingPathComponent("good.bin")) == good)
        #expect(try Data(contentsOf: dir.appendingPathComponent("bad.bin")) == bad)
        #expect(ModelAssetService.installedVersion(in: dir) == "v1")
        // Completed ranges of good.bin were not fetched again.
        let rangesAfter = FakeURLProtocol.requestedRanges(for: manifest.files[0].url).count
        #expect(rangesAfter - rangesBefore < 3)
    }
}
