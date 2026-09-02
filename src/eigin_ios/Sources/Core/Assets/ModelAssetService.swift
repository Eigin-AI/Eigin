import Crypto
import Foundation

/// Downloads and verifies model assets from the relay's self-hosted mirror.
///
/// All on-demand model downloads (Gemma, Plapre Pico, PocketTTS) flow through
/// this: fetch the manifest, stream each file from its presigned URL, verify
/// the SHA-256, and record the installed version on disk.
struct ModelAssetService: Sendable {
    let relay: any RelayClient

    init(relay: any RelayClient = DefaultRelayClient()) {
        self.relay = relay
    }

    /// Marker filename written into each asset's directory on success.
    static let markerName = ".eigin-asset.json"

    /// Fetch the manifest for an asset id via the relay client.
    func manifest(for id: String) async throws -> AssetManifest {
        try await relay.asset(id: id)
    }

    /// Download one manifest file to a destination URL, verifying its SHA-256.
    /// Returns the bytes written. Throws `checksumMismatch` when the digest
    /// doesn't match the manifest.
    static func download(
        file: AssetManifest.File,
        to destination: URL,
        session: URLSession = .shared
    ) async throws -> Int64 {
        guard let url = URL(string: file.url) else {
            throw ModelAssetError.invalidURL(file.path)
        }
        let (tempURL, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else {
            try? FileManager.default.removeItem(at: tempURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModelAssetError.downloadFailed(path: file.path, status: status)
        }

        let actual = (try? Self.sha256Hex(of: tempURL)) ?? ""
        guard actual.caseInsensitiveCompare(file.sha256) == .orderedSame else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ModelAssetError.checksumMismatch(path: file.path)
        }

        let size = (try? FileManager.default
            .attributesOfItem(atPath: tempURL.path)[.size] as? Int64)
        let fm = FileManager.default
        try? fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempURL, to: destination)
        return size ?? 0
    }

    /// Streaming SHA-256 of a file, as lowercase hex.
    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024
        while let chunk = try handle.read(upToCount: bufferSize) {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Write the installed-version marker into an asset directory.
    static func writeMarker(
        id: String, version: String, in directory: URL
    ) {
        let marker = directory.appendingPathComponent(markerName)
        let payload: [String: String] = ["id": id, "version": version]
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: marker, options: .atomic)
        }
    }

    /// Read the installed version from an asset directory's marker, if any.
    static func installedVersion(id: String? = nil, in directory: URL) -> String? {
        let marker = directory.appendingPathComponent(markerName)
        guard let data = try? Data(contentsOf: marker),
              let payload = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        if let id, payload["id"] != id {
            return nil
        }
        return payload["version"]
    }
}

enum ModelAssetError: Error, LocalizedError {
    case invalidURL(String)
    case downloadFailed(path: String, status: Int)
    case checksumMismatch(path: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            "Invalid download URL for \(path)"
        case .downloadFailed(let path, let status):
            "Failed to download \(path) (HTTP \(status))"
        case .checksumMismatch(let path):
            "Checksum mismatch for \(path) — download corrupted"
        }
    }
}
