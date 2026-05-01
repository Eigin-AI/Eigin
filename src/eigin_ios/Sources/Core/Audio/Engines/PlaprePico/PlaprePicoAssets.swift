#if !targetEnvironment(simulator)
import CoreML
import Foundation

/// Manages on-disk layout, HuggingFace download, and CoreML compilation
/// for the Plapre Pico model assets.
///
/// Layout under Caches:
/// ```
/// ~Library/Caches/plapre-pico/
///   PlaprePico_int8.mlmodelc/   (compiled from .mlpackage at download time)
///   KanadeDecoder.mlmodelc/
///   Vocoder.mlmodelc/
///   tokenizer.json
///   tokenizer_config.json
///   speakers.json
///   rope_cos.npy
///   rope_sin.npy
///   manifest.json
/// ```
enum PlaprePicoAssets {
    // MARK: - Paths

    static var rootDirectory: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plapre-pico", isDirectory: true)
    }

    /// Names of the `.mlpackage` directories on HuggingFace that get compiled to `.mlmodelc`.
    /// Uses the full-precision `PlaprePico` variant — the `_int8` variant fails to
    /// compile for ANE (`MILCompilerForANE error`), forcing CPU fallback.
    static let modelPackageNames = [
        "PlaprePico",
        "KanadeDecoder",
        "Vocoder",
    ]

    /// Standalone files (non-package) that need to be downloaded as-is.
    static let supportingFiles = [
        "tokenizer.json",
        "tokenizer_config.json",
        "speakers.json",
        "rope_cos.npy",
        "rope_sin.npy",
        "manifest.json",
    ]

    static func compiledModelURL(_ name: String) -> URL {
        rootDirectory.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
    }

    static func supportingFileURL(_ name: String) -> URL {
        rootDirectory.appendingPathComponent(name)
    }

    // MARK: - Verification

    /// True when every required file/directory is present on disk.
    static func verifyOnDisk() -> Bool {
        let fm = FileManager.default
        for name in modelPackageNames {
            if !fm.fileExists(atPath: compiledModelURL(name).path) { return false }
        }
        for name in supportingFiles {
            if !fm.fileExists(atPath: supportingFileURL(name).path) { return false }
        }
        return true
    }

    // MARK: - Download

    /// Errors raised by the asset download/compile pipeline.
    enum AssetError: Error, LocalizedError {
        case treeListFailed(path: String, status: Int)
        case fileDownloadFailed(path: String, status: Int)
        case compileFailed(model: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .treeListFailed(let path, let status):
                "Failed to list \(path) on HuggingFace (HTTP \(status))"
            case .fileDownloadFailed(let path, let status):
                "Failed to download \(path) from HuggingFace (HTTP \(status))"
            case .compileFailed(let model, let underlying):
                "Failed to compile \(model): \(underlying.localizedDescription)"
            }
        }
    }

    /// Entry in the HuggingFace tree API response.
    private struct TreeEntry: Decodable {
        let type: String // "file" | "directory"
        let path: String
        let size: Int?
    }

    /// Downloads every required asset, compiles each `.mlpackage` to `.mlmodelc`, and
    /// places everything in `rootDirectory`. Reports aggregate progress in [0, 1].
    ///
    /// Idempotent at the file level: existing files in the cache dir are not re-downloaded
    /// (the per-file existence check happens before the network call).
    static func downloadAll(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        // 1. Enumerate every file we need (package contents + supporting files), with sizes.
        var plan: [(remotePath: String, localPath: URL, size: Int)] = []

        for pkg in modelPackageNames {
            let entries = try await listTree(path: "\(pkg).mlpackage")
            let stagingDir = rootDirectory.appendingPathComponent(
                "_staging/\(pkg).mlpackage",
                isDirectory: true
            )
            for entry in entries where entry.type == "file" {
                // entry.path is repo-relative, e.g. "PlaprePico_int8.mlpackage/Manifest.json".
                // Strip the leading package dir to get the path inside the staging area.
                let prefix = "\(pkg).mlpackage/"
                let relative = entry.path.hasPrefix(prefix)
                    ? String(entry.path.dropFirst(prefix.count))
                    : entry.path
                let dest = stagingDir.appendingPathComponent(relative)
                plan.append((entry.path, dest, entry.size ?? 0))
            }
        }

        // The tree API 404s on individual file paths — list the repo root once
        // and look supporting files up by name.
        let rootEntries = try await listTree(path: "")
        for name in supportingFiles {
            let size = rootEntries.first(where: { $0.path == name })?.size ?? 0
            plan.append((name, supportingFileURL(name), size))
        }

        let totalBytes = plan.reduce(0) { $0 + $1.size }
        var downloadedBytes = 0
        progress(0)

        // 2. Download each file (skip if already on disk).
        for item in plan {
            if fm.fileExists(atPath: item.localPath.path) {
                downloadedBytes += item.size
                progress(totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0)
                continue
            }
            try fm.createDirectory(
                at: item.localPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await downloadFile(remotePath: item.remotePath, to: item.localPath)
            downloadedBytes += item.size
            progress(totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0)
        }

        // 3. Compile each .mlpackage from staging to .mlmodelc in the root.
        for pkg in modelPackageNames {
            let compiledDest = compiledModelURL(pkg)
            if fm.fileExists(atPath: compiledDest.path) { continue }
            let stagingPkg = rootDirectory.appendingPathComponent(
                "_staging/\(pkg).mlpackage",
                isDirectory: true
            )
            do {
                let compiled = try await MLModel.compileModel(at: stagingPkg)
                // compileModel returns a temp URL — move it into place.
                if fm.fileExists(atPath: compiledDest.path) {
                    try fm.removeItem(at: compiledDest)
                }
                try fm.moveItem(at: compiled, to: compiledDest)
            } catch {
                throw AssetError.compileFailed(model: pkg, underlying: error)
            }
        }

        // 4. Clean up staging dir — packages no longer needed once compiled.
        let stagingRoot = rootDirectory.appendingPathComponent("_staging", isDirectory: true)
        try? fm.removeItem(at: stagingRoot)

        progress(1)
    }

    /// Removes every cached file. Resets the asset to its undownloaded state.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    // MARK: - HuggingFace API

    private static func listTree(path: String) async throws -> [TreeEntry] {
        let base = "https://huggingface.co/api/models/\(PlaprePicoConfig.hfRepo)/tree/\(PlaprePicoConfig.hfRevision)"
        let urlString = path.isEmpty ? base : "\(base)/\(path)"
        var components = URLComponents(string: urlString)!
        components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
        let url = components.url!

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AssetError.treeListFailed(path: path, status: status)
        }
        return try JSONDecoder().decode([TreeEntry].self, from: data)
    }

    private static func downloadFile(remotePath: String, to destination: URL) async throws {
        let urlString =
            "https://huggingface.co/\(PlaprePicoConfig.hfRepo)/resolve/\(PlaprePicoConfig.hfRevision)/\(remotePath)"
        guard let url = URL(string: urlString) else {
            throw AssetError.fileDownloadFailed(path: remotePath, status: -1)
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AssetError.fileDownloadFailed(path: remotePath, status: status)
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempURL, to: destination)
    }
}
#endif
