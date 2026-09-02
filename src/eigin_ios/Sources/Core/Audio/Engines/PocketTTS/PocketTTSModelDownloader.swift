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

    /// True when FluidAudio's required model directories are all in cache and
    /// no download is mid-flight.
    static func isDownloaded() -> Bool {
        let fm = FileManager.default
        let repoDir = cacheDirectory
        guard AssetDownloadPlan.load(from: repoDir) == nil else { return false }
        return [
            "cond_step.mlmodelc",
            "flowlm_step.mlmodelc",
            "flow_decoder.mlmodelc",
            "mimi_decoder_v2.mlmodelc",
            "constants_bin",
        ].allSatisfy { fm.fileExists(atPath: repoDir.appendingPathComponent($0).path) }
    }

    /// Download every manifest file into the FluidAudio cache layout, verifying
    /// checksums. Resumes partial state; joins an in-flight download.
    static func download() async throws {
        try await AssetDownloader.shared.download(
            .init(assetID: assetID, directory: cacheDirectory)
        )
    }
}
#endif
