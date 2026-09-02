import Crypto
import Foundation

/// Manifest access, checksum, and version-marker helpers for the relay's
/// self-hosted model mirror. The transfer itself is `AssetDownloader`.
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
    case downloadFailed(path: String, status: Int, detail: String = "")
    case rangeNotHonoured(path: String)
    case checksumMismatch(path: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            "Invalid download URL for \(path)"
        case .downloadFailed(let path, let status, let detail):
            "Failed to download \(path) (HTTP \(status))" + (detail.isEmpty ? "" : ": \(detail)")
        case .rangeNotHonoured(let path):
            "Byte range for \(path) came back wrong — download corrupted"
        case .checksumMismatch(let path):
            "Checksum mismatch for \(path) — download corrupted"
        }
    }
}
