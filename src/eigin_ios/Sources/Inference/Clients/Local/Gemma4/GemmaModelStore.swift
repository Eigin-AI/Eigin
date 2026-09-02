import Foundation

/// On-disk layout of the Gemma 4 E2B LiteRT-LM model under `ModelStorage`.
/// Stateless: the download itself runs through `AssetDownloader`.
enum GemmaModelStore {
    /// Mirror asset id. Runtime-specific (LiteRT-LM), so different runtimes of
    /// the same model don't collide in the asset namespace.
    static let assetID = "gemma4-e2b-litertlm"

    /// The single `.litertlm` artifact that makes up the model.
    static let fileName = "gemma-4-E2B-it.litertlm"

    /// Approximate download size, for the pre-download free-space check.
    static let estimatedSize: Int64 = 2_583_691_264

    static var directory: URL {
        ModelStorage.directory(for: assetID)
    }

    /// The model file, or nil when it isn't fully on disk. A download in
    /// progress preallocates the file, so the sidecar's absence is what says
    /// "complete" (installs predating version markers have no marker).
    static var modelURL: URL? {
        let url = directory.appendingPathComponent(fileName)
        guard let size = (try? FileManager.default
            .attributesOfItem(atPath: url.path))?[.size] as? Int64,
            size > 0,
            AssetDownloadPlan.load(from: directory) == nil
        else { return nil }
        return url
    }

    static var isDownloaded: Bool {
        modelURL != nil
    }

    static func delete() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
