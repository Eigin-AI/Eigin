import Foundation

/// One HTTP request in a download: a whole file, or a byte range of a large one.
struct AssetPart: Codable, Hashable, Sendable {
    let fileIndex: Int
    let offset: Int64
    let length: Int64
    let isWhole: Bool

    /// Last byte of the range, inclusive (for the `Range` header).
    var end: Int64 {
        offset + length - 1
    }
}

/// Everything needed to (re)start an asset download: the manifest's files, how
/// they split into parts, and which parts already landed on disk.
///
/// Persisted as a sidecar in the asset directory so a relaunch continues where
/// the background session left off.
struct AssetDownloadPlan: Codable, Sendable {
    let assetID: String
    let version: String
    var files: [AssetManifest.File]
    /// On-disk path of each file, relative to the asset directory.
    let localPaths: [String]
    let parts: [AssetPart]
    var completed: Set<AssetPart> = []
    var chunking: Chunking = .default

    /// When and how large files split into byte ranges.
    struct Chunking: Codable, Sendable, Equatable {
        /// Files at least this large are fetched as concurrent byte ranges.
        var threshold: Int64
        /// Size of each byte range.
        var size: Int64

        static let `default` = Chunking(threshold: 64 << 20, size: 32 << 20)
    }

    /// Sidecar filename inside the asset directory.
    static let sidecarName = ".eigin-download.json"

    /// Split a manifest into parts. Big files' ranges come first so the
    /// concurrent slots fill with the long poles.
    static func make(
        assetID: String,
        manifest: AssetManifest,
        localPath: (String) -> String = { $0 },
        chunking: Chunking = .default
    ) -> AssetDownloadPlan {
        let order = manifest.files.indices.sorted {
            manifest.files[$0].size > manifest.files[$1].size
        }
        var parts: [AssetPart] = []
        for index in order {
            let size = manifest.files[index].size
            if size >= chunking.threshold {
                var offset: Int64 = 0
                while offset < size {
                    let length = min(chunking.size, size - offset)
                    parts.append(.init(
                        fileIndex: index,
                        offset: offset,
                        length: length,
                        isWhole: false
                    ))
                    offset += length
                }
            } else {
                parts.append(.init(fileIndex: index, offset: 0, length: size, isWhole: true))
            }
        }
        return AssetDownloadPlan(
            assetID: assetID,
            version: manifest.version,
            files: manifest.files,
            localPaths: manifest.files.map { localPath($0.path) },
            parts: parts,
            chunking: chunking
        )
    }

    var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    var completedBytes: Int64 {
        completed.reduce(0) { $0 + $1.length }
    }

    var isComplete: Bool {
        completed.count == parts.count
    }

    /// Whether `fileIndex` is a single-request download (vs. ranges).
    func isChunked(fileIndex: Int) -> Bool {
        files[fileIndex].size >= chunking.threshold
    }

    /// Replace presigned URLs with a fresh manifest of the same version.
    func refreshingURLs(from manifest: AssetManifest) -> AssetDownloadPlan {
        let byPath = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.path, $0) })
        var copy = self
        copy.files = files.map { byPath[$0.path] ?? $0 }
        return copy
    }

    /// Forget every completed part of a file (e.g. after a checksum mismatch).
    mutating func reset(fileIndex: Int) {
        completed = completed.filter { $0.fileIndex != fileIndex }
    }

    // MARK: - Sidecar

    static func load(from directory: URL) -> AssetDownloadPlan? {
        let url = directory.appendingPathComponent(sidecarName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AssetDownloadPlan.self, from: data)
    }

    func save(in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.sidecarName)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func remove(from directory: URL) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(sidecarName))
    }
}
