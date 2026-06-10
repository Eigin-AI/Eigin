import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Downloads and caches CoreML models with background URLSession and pause/resume support.
/// Uses up to 4 concurrent connections for faster HuggingFace downloads.
@Observable
public final class GemmaModelDownloader: NSObject, @unchecked Sendable {
    public static let shared = GemmaModelDownloader()

    // MARK: - Observable State

    public var isDownloading = false
    public var isPaused = false
    public var progress: Double = 0
    public var status = ""
    public var availableModels: [ModelInfo] = ModelInfo.defaults
    public var refreshTrigger = 0
    public var downloadingModelId: String?

    /// Stashed by the AppDelegate when iOS relaunches the app for background
    /// `URLSession` events. Invoked from `urlSessionDidFinishEvents` so iOS
    /// knows we're done processing and can suspend the app.
    public var backgroundCompletionHandler: (() -> Void)?

    // MARK: - Private

    private let fileManager = FileManager.default
    private var session: URLSession!
    var currentModel: ModelInfo?
    var destDir: URL?
    var pendingFiles: [DownloadFile] = []
    private var totalBytesForAllFiles: Int64 = 0
    private var downloadContinuation: CheckedContinuation<URL, Error>?

    private static let sessionIdentifier = AppKeys.downloadSessionIdentifier

    // Parallel download state
    private let maxConcurrentDownloads = 4
    var nextFileIndex = 0
    private var completedBytes: Int64 = 0
    var activeDownloadTasks: [Int: URLSessionDownloadTask] = [:]
    private var activeTaskFileIndex: [Int: Int] = [:]
    private var activeTaskBytes: [Int: Int64] = [:]

    /// Task IDs whose delegate callbacks have already been processed.
    /// Used to prevent `reattachInFlightTasks` from resurrecting zombies
    /// that completed before `getAllTasks` finished.
    var completedTaskIDs: Set<Int> = []

    // MARK: - Types

    public struct ModelInfo: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let size: String
        public let downloadURL: String
        public let folderName: String
        public let includeMultimodal: Bool

        public init(
            id: String,
            name: String,
            size: String,
            downloadURL: String,
            folderName: String,
            includeMultimodal: Bool = false
        ) {
            self.id = id
            self.name = name
            self.size = size
            self.downloadURL = downloadURL
            self.folderName = folderName
            self.includeMultimodal = includeMultimodal
        }

        /// Gemma 4 E2B — text-only, ~3.8 GB, ANE-optimized.
        public static let gemma4e2b = ModelInfo(
            id: "gemma4-e2b", name: "Gemma 4 E2B", size: "4 GB",
            downloadURL: "https://huggingface.co/mlboydaisuke/gemma-4-E2B-coreml/resolve/main",
            folderName: "gemma4-e2b",
            includeMultimodal: false
        )

        public static let defaults: [ModelInfo] = [gemma4e2b]

        /// The default model.
        public static var `default`: ModelInfo {
            gemma4e2b
        }
    }

    struct DownloadFile: Codable {
        let remotePath: String
        let localPath: String
        let estimatedSize: Int64

        init(remotePath: String, localPath: String, estimatedSize: Int64) {
            self.remotePath = remotePath
            self.localPath = localPath
            self.estimatedSize = estimatedSize
        }
    }

    private struct PersistedState: Codable {
        let modelId: String
        let totalBytes: Int64
        let files: [DownloadFile]
    }

    // MARK: - Init

    override init() {
        super.init()
        excludeModelsFromBackup()
        cleanGraveyard()
        restorePendingDownload()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForResource = 7200
        config.httpMaximumConnectionsPerHost = maxConcurrentDownloads
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        reattachInFlightTasks()
    }

    /// Rebuild in-memory bookkeeping for download tasks that iOS kept running
    /// while the app was suspended or killed. Without this, delegate callbacks
    /// for those tasks arrive against empty `activeDownloadTasks` and the
    /// "are we done?" check in `fillDownloadSlots` never sees them.
    private func reattachInFlightTasks() {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            let downloadTasks = tasks.compactMap { $0 as? URLSessionDownloadTask }
            DispatchQueue.main.async { [self] in
                for task in downloadTasks {
                    // Skip tasks whose delegate callbacks have already been
                    // handled while we awaited `getAllTasks`; re-adding them
                    // creates zombies that block `finishDownload`.
                    guard !completedTaskIDs.contains(task.taskIdentifier) else { continue }

                    activeDownloadTasks[task.taskIdentifier] = task
                    // Match the task back to its index in pendingFiles by
                    // taskDescription (set when we dispatched it).
                    if let desc = task.taskDescription,
                       let idx = pendingFiles.firstIndex(where: { $0.localPath == desc })
                    {
                        activeTaskFileIndex[task.taskIdentifier] = idx
                    }
                }

                if !downloadTasks.isEmpty {
                    // We're being driven by the URLSession daemon, not paused.
                    isPaused = false
                    isDownloading = true
                    // Un-pausing may unblock earlier delegate callbacks that
                    // bailed; give the gate a kick.
                    fillDownloadSlots()
                } else if isDownloading, isPaused, currentModel != nil {
                    // All tasks completed while the app was killed; nothing to
                    // reattach. Un-pause so fillDownloadSlots can finish.
                    isPaused = false
                    fillDownloadSlots()
                }
            }
        }
    }

    // MARK: - Public

    public func isDownloaded(_ model: ModelInfo) -> Bool {
        if isDownloading, downloadingModelId == model.id { return false }
        return isModelComplete(model)
    }

    public func isModelComplete(_ model: ModelInfo) -> Bool {
        let dest = modelsDirectory.appendingPathComponent(model.folderName)
        for file in Self.expectedFiles(for: model) {
            // Files the downloader treats as optional (404 → skipped) must
            // also be treated as optional here, or a legitimately-complete
            // download is mis-reported as incomplete forever.
            if Self.isOptionalMlmodelcFile(file.localPath) { continue }
            let path = dest.appendingPathComponent(file.localPath).path
            guard fileManager.fileExists(atPath: path),
                  let attrs = try? fileManager.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? Int64, size > 0
            else {
                return false
            }
        }
        return true
    }

    public func localModelURL(for model: ModelInfo) -> URL? {
        let dir = modelsDirectory.appendingPathComponent(model.folderName)
        let chunk1 = dir.appendingPathComponent("chunk1.mlmodelc")
        if fileManager
            .fileExists(atPath: chunk1.appendingPathComponent("weights/weight.bin").path)
        {
            // Invalidate cache if the chunk's declared ctx doesn't match
            // model_config.json (e.g., v0.6.0/0.6.1 downloaded 8K chunks but
            // shipped a 2K model_config). This prevents a load-time error
            // that would otherwise require the user to manually delete.
            if isChunkCtxMismatched(modelDir: dir, chunk1Dir: chunk1) {
                try? fileManager.removeItem(at: dir)
                return nil
            }
            return chunk1
        }
        let modelc = dir.appendingPathComponent("model.mlmodelc")
        if fileManager
            .fileExists(atPath: modelc.appendingPathComponent("weights/weight.bin").path)
        {
            return modelc
        }
        let pkg = dir.appendingPathComponent("model.mlpackage")
        if fileManager
            .fileExists(atPath: pkg
                .appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin").path)
        {
            return pkg
        }
        return nil
    }

    /// Compare chunk1's declared `causal_mask_full` ctx (from model.mil) against
    /// model_config.json's context_length. Returns true on mismatch so callers
    /// can invalidate the cache and force a fresh download.
    private func isChunkCtxMismatched(modelDir: URL, chunk1Dir: URL) -> Bool {
        guard let configData = try? Data(contentsOf: modelDir
            .appendingPathComponent("model_config.json")),
            let json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
            let expected = json["context_length"] as? Int
        else {
            return false // no config to compare against; leave cache alone
        }
        let milURL = chunk1Dir.appendingPathComponent("model.mil")
        guard let mil = try? String(contentsOf: milURL, encoding: .utf8) else {
            return false
        }
        // Look for the causal_mask_full tensor declaration. The shape's last
        // dimension is ctx: e.g. `tensor<fp16, [1, 1, 1, 2048]> causal_mask_full`.
        let pattern = #"tensor<fp16,\s*\[\s*1,\s*1,\s*1,\s*(\d+)\s*\]>\s*causal_mask_full"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: mil, range: NSRange(mil.startIndex..., in: mil)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: mil),
              let actual = Int(mil[range])
        else {
            return false
        }
        return actual != expected
    }

    /// Download a model, skipping files that already exist on disk.
    /// Set `repair: true` to re-check and download any missing files.
    public func download(_ model: ModelInfo, repair: Bool = false) async throws -> URL {
        if !repair, isModelComplete(model) {
            return localModelURL(for: model)!
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [self] in
                // Resume paused download for same model
                if isPaused, currentModel?.id == model.id {
                    downloadContinuation = continuation
                    resumeDownload()
                    return
                }

                // Cancel any in-progress download for a different model
                if isDownloading {
                    cancelDownload()
                }

                downloadContinuation = continuation
                currentModel = model
                downloadingModelId = model.id
                isDownloading = true
                isPaused = false
                progress = 0
                status = "Starting..."

                let dest = modelsDirectory.appendingPathComponent(model.folderName)
                destDir = dest
                try? fileManager.removeItem(at: dest)
                try? fileManager.createDirectory(at: dest, withIntermediateDirectories: true)

                if model.downloadURL.contains("huggingface.co") {
                    buildHuggingFaceFileList(model)
                } else {
                    pendingFiles = [DownloadFile(
                        remotePath: model.downloadURL,
                        localPath: "__archive.zip",
                        estimatedSize: 350_000_000
                    )]
                    totalBytesForAllFiles = 350_000_000
                    completedBytes = 0
                    nextFileIndex = 0
                }
                fillDownloadSlots()
            }
        }
    }

    public func pause() {
        guard isDownloading, !isPaused else { return }
        isPaused = true
        status = "Paused"

        // Cancel all active tasks. On resume, incomplete files are re-downloaded.
        for task in activeDownloadTasks.values {
            task.cancel()
        }
        activeDownloadTasks.removeAll()
        activeTaskFileIndex.removeAll()
        activeTaskBytes.removeAll()
        saveState()
    }

    public func resumeDownload() {
        guard isPaused else { return }
        isPaused = false
        status = "Resuming..."

        // Re-scan from beginning — fillDownloadSlots skips completed files on disk.
        nextFileIndex = 0
        completedBytes = 0
        fillDownloadSlots()
    }

    public func cancelDownload() {
        for task in activeDownloadTasks.values {
            task.cancel()
        }
        activeDownloadTasks.removeAll()
        activeTaskFileIndex.removeAll()
        activeTaskBytes.removeAll()
        completedTaskIDs.removeAll()
        nextFileIndex = 0
        completedBytes = 0
        isDownloading = false
        isPaused = false
        progress = 0
        status = ""
        downloadingModelId = nil
        pendingFiles = []
        cleanupPersistedState()

        if let dest = destDir {
            try? fileManager.removeItem(at: dest)
        }

        downloadContinuation?.resume(throwing: CancellationError())
        downloadContinuation = nil
    }

    public func delete(_ model: ModelInfo) throws {
        if isDownloading, currentModel?.id == model.id {
            cancelDownload()
        }
        let dir = modelsDirectory.appendingPathComponent(model.folderName)
        defer { refreshTrigger += 1 }
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try evictToGraveyard(dir)
    }

    /// Remove every model folder under `modelsDirectory`. Used as an escape
    /// hatch when a stale/incompatible artifact from a prior app version
    /// can't be deleted via the per-model trash button.
    public func resetAllModels() throws {
        cancelDownload()
        defer { refreshTrigger += 1 }
        guard fileManager.fileExists(atPath: modelsDirectory.path) else { return }
        let children = (try? fileManager.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var firstError: Error?
        for child in children {
            // Skip the graveyard itself — it gets cleaned asynchronously.
            if child.lastPathComponent.hasPrefix(".graveyard-") { continue }
            do { try evictToGraveyard(child) }
            catch { if firstError == nil { firstError = error } }
        }
        if let e = firstError { throw e }
    }

    /// Move a file / directory out of sight by renaming it into a hidden
    /// graveyard folder, then best-effort delete. Rename succeeds on APFS
    /// even when URLSession background tasks still hold open handles to
    /// files inside — whereas `removeItem` on the same path fails with
    /// "no permission to access" because of those handles.
    ///
    /// The visible model folder disappears immediately. Remaining graveyard
    /// bytes are swept up by `cleanGraveyard` at the next init.
    private func evictToGraveyard(_ url: URL) throws {
        let graveRoot = modelsDirectory.appendingPathComponent(".graveyard", isDirectory: true)
        try? fileManager.createDirectory(at: graveRoot, withIntermediateDirectories: true)
        let grave = graveRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.moveItem(at: url, to: grave)
        try? fileManager.removeItem(at: grave) // best-effort; leftovers cleaned next launch
    }

    /// Best-effort removal of any graveyard residue from prior sessions.
    /// Called on init — by then the URLSession daemon from the prior app
    /// run has released its file handles, so removeItem usually succeeds.
    private func cleanGraveyard() {
        let graveRoot = modelsDirectory.appendingPathComponent(".graveyard", isDirectory: true)
        guard fileManager.fileExists(atPath: graveRoot.path) else { return }
        if let children = try? fileManager.contentsOfDirectory(
            at: graveRoot, includingPropertiesForKeys: nil, options: []
        ) {
            for c in children {
                try? fileManager.removeItem(at: c)
            }
        }
        try? fileManager.removeItem(at: graveRoot)
    }

    // MARK: - Parallel Download Scheduling

    /// Start downloads until we have `maxConcurrentDownloads` active tasks,
    /// or all files are dispatched. Skips files that already exist on disk.
    func fillDownloadSlots() {
        guard !isPaused else {
            saveState()
            return
        }

        while activeDownloadTasks.count < maxConcurrentDownloads,
              nextFileIndex < pendingFiles.count
        {
            let idx = nextFileIndex
            nextFileIndex += 1

            let file = pendingFiles[idx]
            guard let dest = destDir else { continue }
            let destFile = dest.appendingPathComponent(file.localPath)

            // Skip already-downloaded files
            if file.localPath != "__archive.zip", fileManager.fileExists(atPath: destFile.path) {
                let existingSize = (try? fileManager
                    .attributesOfItem(atPath: destFile.path))?[.size] as? Int64 ?? 0
                if existingSize > 0 {
                    completedBytes += existingSize
                    updateProgress()
                    continue
                }
            }

            // Build URL
            let urlString: String
            if file.remotePath.hasPrefix("http") {
                urlString = file.remotePath
            } else if let model = currentModel {
                urlString = "\(model.downloadURL)/\(file.remotePath)"
            } else {
                continue
            }

            guard let url = URL(string: urlString) else { continue }

            try? fileManager.createDirectory(
                at: destFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let task = session.downloadTask(with: url)
            task.taskDescription = file.localPath
            task.resume()

            activeDownloadTasks[task.taskIdentifier] = task
            activeTaskFileIndex[task.taskIdentifier] = idx
        }

        // All files dispatched and all tasks completed → finish
        if activeDownloadTasks.isEmpty, nextFileIndex >= pendingFiles.count {
            finishDownload()
            return
        }

        saveState()
    }

    private func updateProgress() {
        let inFlight = activeTaskBytes.values.reduce(0 as Int64, +)
        let total = Double(max(totalBytesForAllFiles, 1))
        let done = Double(completedBytes + inFlight)
        progress = min(done / total, 0.99)
        let mbDone = done / 1_000_000
        let mbTotal = Double(totalBytesForAllFiles) / 1_000_000
        status = String(format: "%.0f / %.0f MB", mbDone, mbTotal)
    }

    private func finishDownload() {
        guard let model = currentModel, let dest = destDir else { return }

        // Share decode weights with prefill chunks (saves ~1.1 GB)
        for i in 1 ... 4 {
            let src = dest.appendingPathComponent("chunk\(i).mlmodelc/weights/weight.bin")
            let dst = dest.appendingPathComponent("prefill_chunk\(i).mlmodelc/weights/weight.bin")
            if fileManager.fileExists(atPath: src.path), !fileManager.fileExists(atPath: dst.path) {
                try? fileManager.createDirectory(
                    at: dst.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? fileManager.copyItem(at: src, to: dst)
            }
        }

        cleanupPersistedState()
        isDownloading = false
        isPaused = false
        downloadingModelId = nil
        progress = 1.0
        status = "Ready"

        let resolved = localModelURL(for: model)

        if let url = resolved {
            downloadContinuation?.resume(returning: url)
        } else {
            downloadContinuation?.resume(throwing: DownloadError.extractionFailed)
        }
        downloadContinuation = nil
    }

    // MARK: - Persistence

    private var stateURL: URL {
        modelsDirectory.appendingPathComponent(".download_state.json")
    }

    private func saveState() {
        guard let model = currentModel else { return }
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let state = PersistedState(
            modelId: model.id,
            totalBytes: totalBytesForAllFiles,
            files: pendingFiles
        )
        try? JSONEncoder().encode(state).write(to: stateURL)
    }

    private func cleanupPersistedState() {
        try? fileManager.removeItem(at: stateURL)
    }

    private func restorePendingDownload() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data),
              let model = availableModels.first(where: { $0.id == state.modelId }) else { return }

        if localModelURL(for: model) != nil {
            cleanupPersistedState()
            return
        }

        currentModel = model
        destDir = modelsDirectory.appendingPathComponent(model.folderName)
        pendingFiles = state.files
        totalBytesForAllFiles = state.totalBytes
        nextFileIndex = 0
        completedBytes = 0
        downloadingModelId = model.id
        isDownloading = true
        isPaused = true
        // Scan completed bytes from disk for accurate progress
        if let dest = destDir {
            for file in pendingFiles {
                let path = dest.appendingPathComponent(file.localPath).path
                if let attrs = try? fileManager.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? Int64, size > 0
                {
                    completedBytes += size
                }
            }
        }
        progress = Double(completedBytes) / Double(max(totalBytesForAllFiles, 1))
        status = "Paused"
    }

    // MARK: - HuggingFace File List

    static func expectedFiles(for model: ModelInfo) -> [DownloadFile] {
        func mlc(
            _ remoteDir: String,
            _ remoteName: String,
            _ localName: String,
            weightSize: Int64
        ) -> [DownloadFile] {
            [
                .init(
                    remotePath: "\(remoteDir)/\(remoteName).mlmodelc/weights/weight.bin",
                    localPath: "\(localName).mlmodelc/weights/weight.bin",
                    estimatedSize: weightSize
                ),
                .init(
                    remotePath: "\(remoteDir)/\(remoteName).mlmodelc/coremldata.bin",
                    localPath: "\(localName).mlmodelc/coremldata.bin",
                    estimatedSize: 1000
                ),
                .init(
                    remotePath: "\(remoteDir)/\(remoteName).mlmodelc/model.mil",
                    localPath: "\(localName).mlmodelc/model.mil",
                    estimatedSize: 450_000
                ),
                .init(
                    remotePath: "\(remoteDir)/\(remoteName).mlmodelc/metadata.json",
                    localPath: "\(localName).mlmodelc/metadata.json",
                    estimatedSize: 8000
                ),
                .init(
                    remotePath: "\(remoteDir)/\(remoteName).mlmodelc/analytics/coremldata.bin",
                    localPath: "\(localName).mlmodelc/analytics/coremldata.bin",
                    estimatedSize: 250
                ),
            ]
        }

        func prefillMeta(_ remoteName: String, _ localName: String) -> [DownloadFile] {
            [
                .init(
                    remotePath: "prefill/\(remoteName).mlmodelc/coremldata.bin",
                    localPath: "\(localName).mlmodelc/coremldata.bin",
                    estimatedSize: 1000
                ),
                .init(
                    remotePath: "prefill/\(remoteName).mlmodelc/model.mil",
                    localPath: "\(localName).mlmodelc/model.mil",
                    estimatedSize: 450_000
                ),
                .init(
                    remotePath: "prefill/\(remoteName).mlmodelc/metadata.json",
                    localPath: "\(localName).mlmodelc/metadata.json",
                    estimatedSize: 8000
                ),
                .init(
                    remotePath: "prefill/\(remoteName).mlmodelc/analytics/coremldata.bin",
                    localPath: "\(localName).mlmodelc/analytics/coremldata.bin",
                    estimatedSize: 250
                ),
            ]
        }

        let chunkFiles = mlc("swa", "chunk1", "chunk1", weightSize: 155_436_864)
            + mlc("swa", "chunk2", "chunk2", weightSize: 133_963_968)
            + mlc("swa", "chunk3", "chunk3", weightSize: 325_282_880)
            + mlc("swa", "chunk4", "chunk4", weightSize: 526_874_880)
        let prefillFiles = prefillMeta("chunk1", "prefill_chunk1")
            + prefillMeta("chunk2", "prefill_chunk2")
            + prefillMeta("chunk3", "prefill_chunk3")
            + prefillMeta("chunk4", "prefill_chunk4")

        let textFiles: [DownloadFile] = [
            .init(
                remotePath: "model_config.json",
                localPath: "model_config.json",
                estimatedSize: 500
            ),
            .init(
                remotePath: "hf_model/tokenizer.json",
                localPath: "hf_model/tokenizer.json",
                estimatedSize: 30_000_000
            ),
            .init(
                remotePath: "hf_model/tokenizer_config.json",
                localPath: "hf_model/tokenizer_config.json",
                estimatedSize: 5000
            ),
            .init(
                remotePath: "hf_model/config.json",
                localPath: "hf_model/config.json",
                estimatedSize: 5000
            ),
            .init(
                remotePath: "embed_tokens_q8.bin",
                localPath: "embed_tokens_q8.bin",
                estimatedSize: 402_653_184
            ),
            .init(
                remotePath: "embed_tokens_scales.bin",
                localPath: "embed_tokens_scales.bin",
                estimatedSize: 524_288
            ),
            .init(
                remotePath: "embed_tokens_per_layer_q8.bin",
                localPath: "embed_tokens_per_layer_q8.bin",
                estimatedSize: 2_348_810_240
            ),
            .init(
                remotePath: "embed_tokens_per_layer_scales.bin",
                localPath: "embed_tokens_per_layer_scales.bin",
                estimatedSize: 524_288
            ),
            .init(
                remotePath: "per_layer_projection.bin",
                localPath: "per_layer_projection.bin",
                estimatedSize: 27_525_120
            ),
            .init(
                remotePath: "per_layer_norm_weight.bin",
                localPath: "per_layer_norm_weight.bin",
                estimatedSize: 1024
            ),
            .init(
                remotePath: "swa/cos_sliding.npy",
                localPath: "cos_sliding.npy",
                estimatedSize: 4_194_432
            ),
            .init(
                remotePath: "swa/sin_sliding.npy",
                localPath: "sin_sliding.npy",
                estimatedSize: 4_194_432
            ),
            .init(
                remotePath: "swa/cos_full.npy",
                localPath: "cos_full.npy",
                estimatedSize: 8_388_736
            ),
            .init(
                remotePath: "swa/sin_full.npy",
                localPath: "sin_full.npy",
                estimatedSize: 8_388_736
            ),
        ]

        let multimodalFiles: [DownloadFile] = [
            .init(
                remotePath: "vision.mlmodelc/weights/weight.bin",
                localPath: "vision.mlmodelc/weights/weight.bin",
                estimatedSize: 320_000_000
            ),
            .init(
                remotePath: "vision.mlmodelc/coremldata.bin",
                localPath: "vision.mlmodelc/coremldata.bin",
                estimatedSize: 200_000
            ),
            .init(
                remotePath: "vision.mlmodelc/model.mil",
                localPath: "vision.mlmodelc/model.mil",
                estimatedSize: 50000
            ),
            .init(
                remotePath: "vision.mlmodelc/metadata.json",
                localPath: "vision.mlmodelc/metadata.json",
                estimatedSize: 1000
            ),
            .init(
                remotePath: "vision.mlmodelc/analytics/coremldata.bin",
                localPath: "vision.mlmodelc/analytics/coremldata.bin",
                estimatedSize: 1000
            ),
            .init(
                remotePath: "audio.mlmodelc/weights/weight.bin",
                localPath: "audio.mlmodelc/weights/weight.bin",
                estimatedSize: 295_373_248
            ),
            .init(
                remotePath: "audio.mlmodelc/coremldata.bin",
                localPath: "audio.mlmodelc/coremldata.bin",
                estimatedSize: 1000
            ),
            .init(
                remotePath: "audio.mlmodelc/model.mil",
                localPath: "audio.mlmodelc/model.mil",
                estimatedSize: 759_000
            ),
            .init(
                remotePath: "audio.mlmodelc/metadata.json",
                localPath: "audio.mlmodelc/metadata.json",
                estimatedSize: 3000
            ),
            .init(
                remotePath: "audio.mlmodelc/analytics/coremldata.bin",
                localPath: "audio.mlmodelc/analytics/coremldata.bin",
                estimatedSize: 250
            ),
            .init(
                remotePath: "mel_filterbank.bin",
                localPath: "mel_filterbank.bin",
                estimatedSize: 131_584
            ),
            .init(
                remotePath: "audio_config.json",
                localPath: "audio_config.json",
                estimatedSize: 500
            ),
            .init(
                remotePath: "output_proj_weight.npy",
                localPath: "output_proj_weight.npy",
                estimatedSize: 3_145_856
            ),
            .init(
                remotePath: "output_proj_bias.npy",
                localPath: "output_proj_bias.npy",
                estimatedSize: 3200
            ),
            .init(
                remotePath: "embed_proj_weight.npy",
                localPath: "embed_proj_weight.npy",
                estimatedSize: 4_718_720
            ),
        ]

        let extraFiles = textFiles + (model.includeMultimodal ? multimodalFiles : [])
        return chunkFiles + prefillFiles + extraFiles
    }

    static func expectedFileSizeBytes(for model: ModelInfo) -> Int64 {
        expectedFiles(for: model).reduce(into: 0) { $0 += $1.estimatedSize }
    }

    private func buildHuggingFaceFileList(_ model: ModelInfo) {
        let allFiles = Self.expectedFiles(for: model)
        let threshold: Int64 = 10_000_000
        var largeFiles: [DownloadFile] = []
        var smallFiles: [DownloadFile] = []
        for file in allFiles {
            if file.estimatedSize >= threshold {
                largeFiles.append(file)
            } else {
                smallFiles.append(file)
            }
        }
        largeFiles.sort { $0.estimatedSize > $1.estimatedSize }
        pendingFiles = largeFiles + smallFiles
        totalBytesForAllFiles = pendingFiles.reduce(0) { $0 + $1.estimatedSize }
        completedBytes = 0
        nextFileIndex = 0
    }

    // MARK: - ZIP

    private func unzipFile(_ zipURL: URL, to destDir: URL) throws {
#if os(macOS)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-xk", zipURL.path, destDir.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
#else
        try extractZipNative(from: zipURL, to: destDir)
#endif
    }

#if !os(macOS)
    private func extractZipNative(from zipURL: URL, to destDir: URL) throws {
        let data = try Data(contentsOf: zipURL)
        guard data.count > 22 else { throw DownloadError.extractionFailed }
        var eocdOffset = data.count - 22
        while eocdOffset >= 0 {
            if data[eocdOffset] == 0x50, data[eocdOffset + 1] == 0x4B,
               data[eocdOffset + 2] == 0x05, data[eocdOffset + 3] == 0x06 { break }
            eocdOffset -= 1
        }
        guard eocdOffset >= 0 else { throw DownloadError.extractionFailed }
        let cdOffset = Int(data[eocdOffset + 16 ..< eocdOffset + 20]
            .withUnsafeBytes { $0.load(as: UInt32.self) })
        let cdCount = Int(data[eocdOffset + 10 ..< eocdOffset + 12]
            .withUnsafeBytes { $0.load(as: UInt16.self) })
        var pos = cdOffset
        for _ in 0 ..< cdCount {
            guard data[pos] == 0x50, data[pos + 1] == 0x4B else { break }
            let uncompSize = Int(data[pos + 24 ..< pos + 28]
                .withUnsafeBytes { $0.load(as: UInt32.self) })
            let nameLen = Int(data[pos + 28 ..< pos + 30]
                .withUnsafeBytes { $0.load(as: UInt16.self) })
            let extraLen = Int(data[pos + 30 ..< pos + 32]
                .withUnsafeBytes { $0.load(as: UInt16.self) })
            let commentLen = Int(data[pos + 32 ..< pos + 34]
                .withUnsafeBytes { $0.load(as: UInt16.self) })
            let localOffset = Int(data[pos + 42 ..< pos + 46]
                .withUnsafeBytes { $0.load(as: UInt32.self) })
            let name = String(data: data[pos + 46 ..< pos + 46 + nameLen], encoding: .utf8) ?? ""
            let destPath = destDir.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try fileManager.createDirectory(at: destPath, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: destPath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let lnl = Int(data[localOffset + 26 ..< localOffset + 28]
                    .withUnsafeBytes { $0.load(as: UInt16.self) })
                let lel = Int(data[localOffset + 28 ..< localOffset + 30]
                    .withUnsafeBytes { $0.load(as: UInt16.self) })
                let ds = localOffset + 30 + lnl + lel
                try Data(data[ds ..< ds + uncompSize]).write(to: destPath)
            }
            pos += 46 + nameLen + extraLen + commentLen
        }
    }
#endif

    /// Files inside an mlmodelc that CoreML doesn't require to load the model.
    /// A 404 on these shouldn't abort the whole download — the upload process
    /// for W8A8 has historically produced HF repos missing `coremldata.bin`
    /// (since fixed) and `metadata.json` (still missing in some uploads); the
    /// latter is purely descriptive. Keep this list conservative — anything
    /// not listed here is treated as required.
    static func isOptionalMlmodelcFile(_ localPath: String) -> Bool {
        localPath.hasSuffix(".mlmodelc/metadata.json")
            || localPath.hasSuffix(".mlmodelc/analytics/coremldata.bin")
    }

    /// Exclude the Models directory from iCloud and iTunes backups.
    /// The ~3.8 GB of model weights are re-downloadable, so backing them up
    /// wastes the user's iCloud quota. Called once on init; safe to call
    /// repeatedly (it's a no-op if the attribute is already set).
    private func excludeModelsFromBackup() {
        var dir = modelsDirectory
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
        } catch {
            // Non-fatal: the model still works; it just won't be excluded from backup.
            AppLogger.warning(
                "GemmaModelDownloader: could not exclude Models from backup: \(public: error.localizedDescription)",
                category: .chat
            )
        }
    }

    private var modelsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models")
    }
}

// MARK: - URLSession Delegate

extension GemmaModelDownloader: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let localPath = downloadTask.taskDescription,
              let dest = destDir else { return }

        // HTTP status check: URLSessionDownloadTask writes the response body
        // to `location` regardless of status code. A 404 from HuggingFace is
        // a short HTML page ("Entry not found") that would otherwise be
        // saved verbatim and later fail a checksum / signature check with
        // a misleading error. Catch it here with a clear error.
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode >= 400 {
            // Read a small excerpt of the body for the error message.
            let snippet: String = (try? String(contentsOf: location, encoding: .utf8))?
                .prefix(200).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try? fileManager.removeItem(at: location)
            let url = downloadTask.originalRequest?.url?.absoluteString ?? "(unknown)"
            let taskId = downloadTask.taskIdentifier

            // Optional files: metadata.json and analytics/coremldata.bin inside
            // an mlmodelc are descriptive, not functional — CoreML loads fine
            // without them. Treat 404 on these as non-fatal so a slightly
            // incomplete HF upload doesn't abort the entire download.
            if http.statusCode == 404, Self.isOptionalMlmodelcFile(localPath) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    activeDownloadTasks.removeValue(forKey: taskId)
                    activeTaskFileIndex.removeValue(forKey: taskId)
                    activeTaskBytes.removeValue(forKey: taskId)
                    fillDownloadSlots()
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                activeDownloadTasks.removeValue(forKey: taskId)
                activeTaskFileIndex.removeValue(forKey: taskId)
                activeTaskBytes.removeValue(forKey: taskId)
                status = "Error: HTTP \(http.statusCode) for \(localPath)"
                // Surface the actual server message so the user sees *why* it failed
                // (e.g., "Entry not found. Please check the file URL.").
                let err = NSError(
                    domain: "Local.ModelDownloader",
                    code: http.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "HTTP \(http.statusCode) fetching \(url). " +
                            (snippet.isEmpty ? "" : "Server: \(snippet)"),
                    ]
                )
                isDownloading = false
                downloadingModelId = nil
                downloadContinuation?.resume(throwing: err)
                downloadContinuation = nil
            }
            return
        }

        let destFile = dest.appendingPathComponent(localPath)

        // Must move synchronously before this method returns
        try? fileManager.createDirectory(
            at: destFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: destFile)
        try? fileManager.moveItem(at: location, to: destFile)

        let downloadedSize = (try? fileManager
            .attributesOfItem(atPath: destFile.path))?[.size] as? Int64 ?? 0
        let isZip = localPath == "__archive.zip"
        let taskId = downloadTask.taskIdentifier

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            completedTaskIDs.insert(taskId)
            activeDownloadTasks.removeValue(forKey: taskId)
            activeTaskFileIndex.removeValue(forKey: taskId)
            activeTaskBytes.removeValue(forKey: taskId)
            completedBytes += downloadedSize
            updateProgress()

            if isZip {
                status = "Extracting..."
                DispatchQueue.global(qos: .userInitiated).async {
                    try? self.unzipFile(destFile, to: dest)
                    try? self.fileManager.removeItem(at: destFile)
                    DispatchQueue.main.async {
                        self.fillDownloadSlots()
                    }
                }
            } else {
                fillDownloadSlots()
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            activeTaskBytes[taskId] = totalBytesWritten
            updateProgress()
        }
    }

    /// Called when all background-session events for this launch have been
    /// delivered. Invoke the completion handler stashed by the AppDelegate so
    /// iOS knows we're done and can suspend the app.
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let handler = backgroundCompletionHandler
            backgroundCompletionHandler = nil
            // Defer one more main-queue turn so any pending notification-add
            // IPC has time to commit before the app suspends.
            DispatchQueue.main.async { [handler] in
                handler?()
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        if (error as NSError).code == NSURLErrorCancelled {
            DispatchQueue.main.async { [weak self] in
                self?.completedTaskIDs.insert(taskId)
                self?.activeDownloadTasks.removeValue(forKey: taskId)
                self?.activeTaskFileIndex.removeValue(forKey: taskId)
                self?.activeTaskBytes.removeValue(forKey: taskId)
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            completedTaskIDs.insert(taskId)
            activeDownloadTasks.removeValue(forKey: taskId)
            activeTaskFileIndex.removeValue(forKey: taskId)
            activeTaskBytes.removeValue(forKey: taskId)

            // Any non-cancelled task failure borks the whole download.
            // Cancel remaining tasks and clean up partial artifacts.
            let remainingTasks = activeDownloadTasks.values
            for t in remainingTasks {
                t.cancel()
            }
            activeDownloadTasks.removeAll()
            activeTaskFileIndex.removeAll()
            activeTaskBytes.removeAll()
            nextFileIndex = pendingFiles.count // prevent new tasks from starting

            status = "Error: \(error.localizedDescription)"
            isDownloading = false
            isPaused = false
            downloadingModelId = nil
            cleanupPersistedState()
            if let dest = destDir {
                try? fileManager.removeItem(at: dest)
            }
            downloadContinuation?.resume(throwing: error)
            downloadContinuation = nil
        }
    }
}

public enum DownloadError: LocalizedError {
    case invalidURL, extractionFailed
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid download URL"
        case .extractionFailed: "Failed to extract model"
        }
    }
}
