#if !targetEnvironment(simulator)
import FluidAudio
import Foundation

/// Downloads the PocketTTS models from the self-hosted asset mirror into
/// FluidAudio's expected cache layout. Because it seeds FluidAudio's own cache,
/// FluidAudio's built-in downloader (`PocketTtsResourceDownloader`) sees a
/// complete cache and never fetches from HuggingFace.
///
/// Layout (what `PocketTtsResourceDownloader.ensureModels` expects):
/// ```
/// ~Library/Caches/fluidaudio/Models/pocket-tts/
///   cond_step.mlmodelc/…
///   flowlm_step.mlmodelc/…
///   flow_decoder.mlmodelc/…
///   mimi_decoder_v2.mlmodelc/…
///   constants_bin/…
///   .eigin-asset.json   (installed-version marker)
/// ```
enum PocketTTSModelDownloader {
    static let assetID = "pocket-tts-coreml"

    static var cacheDirectory: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fluidaudio/Models/pocket-tts", isDirectory: true)
    }

    /// True when FluidAudio's required model directories are all in cache.
    static func isDownloaded() -> Bool {
        let fm = FileManager.default
        let repoDir = cacheDirectory
        return [
            "cond_step.mlmodelc",
            "flowlm_step.mlmodelc",
            "flow_decoder.mlmodelc",
            "mimi_decoder_v2.mlmodelc",
            "constants_bin",
        ].allSatisfy { fm.fileExists(atPath: repoDir.appendingPathComponent($0).path) }
    }

    /// Download every manifest file into the FluidAudio cache layout,
    /// verifying checksums. Idempotent at the file level.
    static func download(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let manifest = try await ModelAssetService().manifest(for: assetID)
        try FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true
        )

        let totalBytes = manifest.files.reduce(Int64(0)) { $0 + $1.size }
        var completedBytes: Int64 = 0
        progress(0)

        for file in manifest.files {
            let destination = cacheDirectory.appendingPathComponent(file.path)
            if FileManager.default.fileExists(atPath: destination.path) {
                completedBytes += file.size
                progress(totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0)
                continue
            }
            completedBytes += try await ModelAssetService.download(file: file, to: destination)
            progress(totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0)
        }

        ModelAssetService.writeMarker(
            id: assetID, version: manifest.version, in: cacheDirectory
        )
        progress(1)
    }
}
#endif
