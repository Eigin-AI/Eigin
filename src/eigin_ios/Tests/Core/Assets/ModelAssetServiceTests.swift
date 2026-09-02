import Crypto
@testable import Eigin
import Foundation
import Testing

/// ModelAssetService verification + version marker round-trip, against temp files.
@Suite(.serialized)
struct ModelAssetServiceTests {
    private func tempFile(data: Data, name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func sha256MatchesCryptoFramework() throws {
        let data = Data("hello mirror".utf8)
        let file = try tempFile(data: data)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try ModelAssetService.sha256Hex(of: file) == sha256(data))
    }

    @Test func sha256HandlesLargeFiles() throws {
        // 3 MB stream — exercises the chunked read loop.
        let data = Data((0 ..< 3_000_000).map { UInt8(truncatingIfNeeded: $0 % 251) })
        let file = try tempFile(data: data)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try ModelAssetService.sha256Hex(of: file).count == 64)
        #expect(try ModelAssetService.sha256Hex(of: file) == sha256(data))
    }

    @Test func markerRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(ModelAssetService.installedVersion(in: dir) == nil)

        ModelAssetService.writeMarker(id: "gemma4-e2b", version: "2026-01-15-1448", in: dir)
        #expect(ModelAssetService.installedVersion(in: dir) == "2026-01-15-1448")
        #expect(ModelAssetService.installedVersion(id: "gemma4-e2b", in: dir) == "2026-01-15-1448")
        #expect(ModelAssetService.installedVersion(id: "other-id", in: dir) == nil)
    }

    // MARK: - download (verify + move)

    @Test func downloadVerifiesChecksumAndMovesIntoPlace() async throws {
        let bytes = Data("model weights".utf8)
        let urlString = "https://assets.test/gemma/model.bin"
        FakeURLProtocol.stubResponse(for: urlString, data: bytes, statusCode: 200)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-\(UUID().uuidString)/model.bin")
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }

        let file = AssetManifest.File(
            path: "model.bin", size: Int64(bytes.count), sha256: sha256(bytes), url: urlString
        )
        let written = try await ModelAssetService.download(
            file: file, to: dest, session: FakeURLProtocol.fakeSession()
        )

        #expect(written == Int64(bytes.count))
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(try Data(contentsOf: dest) == bytes)
    }

    @Test func downloadRejectsChecksumMismatch() async throws {
        let bytes = Data("corrupted".utf8)
        let urlString = "https://assets.test/gemma/bad.bin"
        FakeURLProtocol.stubResponse(for: urlString, data: bytes, statusCode: 200)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-\(UUID().uuidString)/bad.bin")
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }

        let file = AssetManifest.File(
            path: "bad.bin", size: Int64(bytes.count),
            sha256: "0000000000000000000000000000000000000000000000000000000000000000",
            url: urlString
        )

        await #expect(throws: ModelAssetError.self) {
            _ = try await ModelAssetService.download(
                file: file, to: dest, session: FakeURLProtocol.fakeSession()
            )
        }
        // A mismatched file is never left at the destination.
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    @Test func downloadSurfacesHTTPError() async throws {
        let urlString = "https://assets.test/gemma/missing.bin"
        FakeURLProtocol.stubResponse(for: urlString, data: Data("nope".utf8), statusCode: 403)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-\(UUID().uuidString)/missing.bin")
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }

        let file = AssetManifest.File(path: "missing.bin", size: 4, sha256: "aa", url: urlString)
        await #expect(throws: ModelAssetError.self) {
            _ = try await ModelAssetService.download(
                file: file, to: dest, session: FakeURLProtocol.fakeSession()
            )
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }
}
