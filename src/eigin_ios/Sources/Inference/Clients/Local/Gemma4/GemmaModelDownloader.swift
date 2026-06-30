import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Downloads and caches the on-device model with a background URLSession and
/// pause/resume support. Uses up to 4 concurrent connections for faster
/// HuggingFace downloads.
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

    /// The single `.litertlm` artifact that makes up the model.
    static let modelFileName = "gemma-4-E2B-it.litertlm"

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

        public init(
            id: String,
            name: String,
            size: String,
            downloadURL: String,
            folderName: String
        ) {
            self.id = id
            self.name = name
            self.size = size
            self.downloadURL = downloadURL
            self.folderName = folderName
        }

        /// Gemma 4 E2B — QAT (2/4/8-bit) mobile build for LiteRT-LM, ~2.6 GB.
        /// This is the standard build; its vision/audio encoders are loaded on
        /// demand by the runtime, so they cost nothing while only text is used.
        public static let gemma4e2b = ModelInfo(
            id: "gemma4-e2b", name: "Gemma 4 E2B", size: "2.6 GB",
            downloadURL: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main",
            folderName: "gemma4-e2b-litertlm"
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
        cleanupLegacyCoreMLModel()
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
        let file = modelsDirectory
            .appendingPathComponent(model.folderName)
            .appendingPathComponent(Self.modelFileName)
        guard fileManager.fileExists(atPath: file.path),
              let size = (try? fileManager.attributesOfItem(atPath: file.path))?[.size] as? Int64,
              size > 0
        else { return nil }
        return file
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

                // Models are hosted as individual files on HuggingFace. The
                // LiteRT-LM model is a single `.litertlm` file fetched directly.
                buildHuggingFaceFileList(model)
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

    /// Remove the legacy custom-CoreML Gemma model (chunked `.mlmodelc` engine)
    /// left by versions before the LiteRT-LM migration. Detected by `chunk1.mlmodelc`
    /// in the old `gemma4-e2b` folder; evicted via the graveyard so open handles
    /// from a background session don't block it. The new model lives in a separate
    /// `gemma4-e2b-litertlm` folder, so this never touches the current download.
    private func cleanupLegacyCoreMLModel() {
        let legacyDir = modelsDirectory.appendingPathComponent("gemma4-e2b")
        let chunk1 = legacyDir.appendingPathComponent("chunk1.mlmodelc")
        guard fileManager.fileExists(atPath: chunk1.path) else { return }
        AppLogger.info(
            "Gemma: removing legacy CoreML model at \(public: legacyDir.lastPathComponent)",
            category: .chat
        )
        try? evictToGraveyard(legacyDir)
        UserDefaults.standard.removeObject(forKey: StorageKey.gemmaPrewarmedBuild)
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
            if fileManager.fileExists(atPath: destFile.path) {
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
        guard let model = currentModel else { return }

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

    static func expectedFiles(for _: ModelInfo) -> [DownloadFile] {
        [
            .init(
                remotePath: modelFileName,
                localPath: modelFileName,
                estimatedSize: 2_583_691_264
            ),
        ]
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
        let taskId = downloadTask.taskIdentifier

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            completedTaskIDs.insert(taskId)
            activeDownloadTasks.removeValue(forKey: taskId)
            activeTaskFileIndex.removeValue(forKey: taskId)
            activeTaskBytes.removeValue(forKey: taskId)
            completedBytes += downloadedSize
            updateProgress()
            fillDownloadSlots()
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
