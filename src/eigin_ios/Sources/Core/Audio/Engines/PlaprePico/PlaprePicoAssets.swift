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
    /// Resumes partial downloads; joins an in-flight one.
    static func downloadAll() async throws {
        let fm = FileManager.default
        let uncompiledRoot = rootDirectory.appendingPathComponent(
            uncompiledDirectoryName, isDirectory: true
        )

        // 1. Download. Raw `.mlpackage` trees land in a temporary folder that
        //    only exists until they're compiled; supporting files land in the root.
        try await AssetDownloader.shared.download(
            .init(assetID: assetID, directory: rootDirectory, localPath: localPath)
        )

        // 2. Compile each .mlpackage to .mlmodelc in the root.
        for pkg in modelPackageNames {
            let compiledDest = compiledModelURL(pkg)
            if fm.fileExists(atPath: compiledDest.path) { continue }
            let package = uncompiledRoot.appendingPathComponent(pkg, isDirectory: true)
            do {
                let compiled = try await MLModel.compileModel(at: package)
                // compileModel returns a temp URL — move it into place.
                if fm.fileExists(atPath: compiledDest.path) {
                    try fm.removeItem(at: compiledDest)
                }
                try fm.moveItem(at: compiled, to: compiledDest)
            } catch {
                throw AssetError.compileFailed(model: pkg, underlying: error)
            }
        }

        // 3. Drop the raw packages. The version marker was written by the downloader.
        try? fm.removeItem(at: uncompiledRoot)
    }

    /// Temporary home for downloaded `.mlpackage` trees until they're compiled.
    static let uncompiledDirectoryName = "_uncompiled"

    /// Manifest path → on-disk path: `<Pkg>.mlpackage/x` → `_uncompiled/<Pkg>/x`.
    @Sendable
    static func localPath(_ manifestPath: String) -> String {
        for pkg in modelPackageNames {
            let prefix = "\(pkg).mlpackage/"
            if manifestPath.hasPrefix(prefix) {
                return "\(uncompiledDirectoryName)/\(pkg)/" + manifestPath.dropFirst(prefix.count)
            }
        }
        return manifestPath
    }

    /// Removes every cached file. Resets the asset to its undownloaded state.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
#endif
