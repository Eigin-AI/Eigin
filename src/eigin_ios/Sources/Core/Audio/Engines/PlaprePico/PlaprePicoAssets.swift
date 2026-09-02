#if !targetEnvironment(simulator)
import CoreML
import Foundation

/// Manages on-disk layout, mirror download, and CoreML compilation
/// for the Plapre Pico model assets.
///
/// Layout under Caches:
/// ```
/// ~Library/Caches/plapre-pico/
///   PlaprePico.mlmodelc/   (compiled from .mlpackage at download time)
///   KanadeDecoder.mlmodelc/
///   Vocoder.mlmodelc/
///   tokenizer.json
///   tokenizer_config.json
///   speakers.json
///   rope_cos.npy
///   rope_sin.npy
///   .eigin-asset.json     (installed-version marker)
/// ```
enum PlaprePicoAssets {
    // MARK: - Paths

    /// Mirror asset id. Runtime-specific (CoreML build).
    static let assetID = "plapre-pico-coreml"

    static var rootDirectory: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plapre-pico", isDirectory: true)
    }

    /// Names of the `.mlpackage` directories that get compiled to `.mlmodelc`.
    /// Uses the full-precision `PlaprePico` variant — the `_int8` variant fails to
    /// compile for ANE (`MILCompilerForANE error`), forcing CPU fallback.
    static let modelPackageNames = [
        "PlaprePico",
        "KanadeDecoder",
        "Vocoder",
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
        // Supporting files are only known via the manifest at download time;
        // compiled models present means the download finished and compiled.
        return true
    }

    // MARK: - Download

    /// Errors raised by the asset download/compile pipeline.
    enum AssetError: Error, LocalizedError {
        case compileFailed(model: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .compileFailed(let model, let underlying):
                "Failed to compile \(model): \(underlying.localizedDescription)"
            }
        }
    }

    /// Downloads every required asset from the self-hosted mirror, compiles each
    /// `.mlpackage` to `.mlmodelc`, and places everything in `rootDirectory`.
    /// Reports aggregate progress in [0, 1]. Idempotent at the file level.
    static func downloadAll(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        // 1. The manifest *is* the tree: files, sizes, checksums, URLs.
        let manifest = try await ModelAssetService().manifest(for: assetID)

        let stagingRoot = rootDirectory.appendingPathComponent("_staging", isDirectory: true)
        let totalBytes = manifest.files.reduce(Int64(0)) { $0 + $1.size }
        var downloadedBytes: Int64 = 0
        progress(0)

        // 2. Download each file (skip if already on disk — partial resume).
        for file in manifest.files {
            // .mlpackage trees stage under _staging until compiled; supporting
            // files land directly in the root.
            let destination: URL = if let pkg = modelPackageNames
                .first(where: { file.path.hasPrefix("\($0).mlpackage/") })
            {
                stagingRoot
                    .appendingPathComponent(pkg)
                    .appendingPathComponent(String(file.path.dropFirst("\(pkg).mlpackage/".count)))
            } else {
                supportingFileURL(file.path)
            }

            if fm.fileExists(atPath: destination.path) {
                downloadedBytes += file.size
                progress(totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0)
                continue
            }
            downloadedBytes += try await ModelAssetService.download(
                file: file, to: destination
            )
            progress(totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0)
        }

        // 3. Compile each .mlpackage from staging to .mlmodelc in the root.
        for pkg in modelPackageNames {
            let compiledDest = compiledModelURL(pkg)
            if fm.fileExists(atPath: compiledDest.path) { continue }
            let stagingPkg = stagingRoot.appendingPathComponent(pkg, isDirectory: true)
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

        // 4. Clean up staging + record the installed version.
        try? fm.removeItem(at: stagingRoot)
        ModelAssetService.writeMarker(
            id: assetID, version: manifest.version, in: rootDirectory
        )

        progress(1)
    }

    /// Removes every cached file. Resets the asset to its undownloaded state.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
#endif
