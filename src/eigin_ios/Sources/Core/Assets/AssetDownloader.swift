import Foundation

/// What a caller wants downloaded: one mirror asset into one directory.
struct AssetDownloadRequest: Sendable {
    let assetID: String
    let directory: URL
    /// Maps a manifest path to its on-disk path relative to `directory`.
    let localPath: @Sendable (String) -> String

    init(
        assetID: String,
        directory: URL,
        localPath: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.assetID = assetID
        self.directory = directory
        self.localPath = localPath
    }
}

/// Live progress of one asset download, in bytes.
struct AssetDownloadProgress: Equatable, Sendable {
    var completedBytes: Int64 = 0
    var inFlightBytes: Int64 = 0
    var totalBytes: Int64 = 0

    /// 0...0.99 while transferring; the caller decides what "done" looks like.
    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(Double(completedBytes + inFlightBytes) / Double(totalBytes), 0.99)
    }
}

/// One asset transfer: start a download, observe its progress, and cancel
/// or check it mid-flight.
@MainActor
protocol AssetDownloading {
    func download(_ request: AssetDownloadRequest) async throws
    func observeProgress(
        assetID: String,
        _ update: @escaping @MainActor (AssetDownloadProgress, AssetDownloader.Phase) -> Void
    ) -> Task<Void, Never>
    func cancel(assetID: String)
    func isDownloading(assetID: String) -> Bool
}

extension AssetDownloader: AssetDownloading {}

/// Downloads mirror assets on the app's single background `URLSession`.
///
/// Up to `maxInFlight` requests run at once; large files are split into byte
/// ranges (see `AssetDownloadPlan`) so one file can use every slot. Progress
/// is tracked per part in a sidecar, so an interrupted download resumes on the
/// next `download` call or app launch. Every file is SHA-256 verified before
/// the version marker is written. Assets download one at a time, FIFO.
@Observable
@MainActor
final class AssetDownloader: NSObject {
    /// Where a job is in its lifecycle. Queued covers waiting behind the head
    /// job and initial manifest/plan setup; preparing covers the end-of-transfer
    /// window between "all bytes on disk" and "installed" (the SHA-256 pass).
    enum Phase: Equatable {
        case queued
        case transferring
        case preparing
    }

    static let shared = AssetDownloader(
        configuration: {
            let config = URLSessionConfiguration
                .background(withIdentifier: AppKeys.downloadSessionIdentifier)
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            config.timeoutIntervalForResource = 7200
            config.httpMaximumConnectionsPerHost = AssetDownloader.maxInFlight
            return config
        }(),
        manifest: { try await ModelAssetService().manifest(for: $0) }
    )

    /// Concurrent requests. iOS caps connections per host at 6, so more just queue.
    static let maxInFlight = 6

    /// Byte progress per asset id, present while that asset is queued or transferring.
    private(set) var progress: [String: AssetDownloadProgress] = [:]

    /// Lifecycle phase per asset id, present alongside `progress`.
    private(set) var phases: [String: Phase] = [:]

    /// Stashed by the AppDelegate when iOS relaunches the app for background
    /// session events; called once those events are delivered.
    @ObservationIgnored var backgroundCompletionHandler: (() -> Void)?

    @ObservationIgnored private let fetchManifest: @Sendable (String) async throws -> AssetManifest
    @ObservationIgnored private let registry: AssetDownloadRegistry
    @ObservationIgnored private let chunking: AssetDownloadPlan.Chunking
    @ObservationIgnored private let targets = AssetTaskTargets()
    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var queue: [AssetDownloadJob] = []
    /// False until the session has reported its surviving tasks.
    @ObservationIgnored private var isReady = false

    init(
        configuration: URLSessionConfiguration,
        manifest: @escaping @Sendable (String) async throws -> AssetManifest,
        registry: AssetDownloadRegistry = AssetDownloadRegistry(),
        chunking: AssetDownloadPlan.Chunking = .default
    ) {
        fetchManifest = manifest
        self.registry = registry
        self.chunking = chunking
        super.init()
        restoreJobs()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                self?.reattach(tasks)
            }
        }
    }

    // MARK: - Public

    /// Download an asset, resuming any partial state. Returns once every file
    /// is on disk and verified. Joins the in-flight job if one exists for
    /// the same asset id.
    func download(_ request: AssetDownloadRequest) async throws {
        let job = queue.first { $0.request.assetID == request.assetID }
            ?? enqueue(AssetDownloadJob(request: request))
        // A job restored from the sidecar only knows its directory; take the
        // caller's path mapping in case the plan has to be rebuilt.
        if !job.hasFreshURLs { job.request = request }
        let assetID = request.assetID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                job.continuations.append(continuation)
                pump()
            }
        } onCancel: {
            Task { @MainActor in self.cancel(assetID: assetID) }
        }
    }

    /// Stop and discard a download, deleting partial files. Awaiting callers
    /// get `CancellationError`.
    func cancel(assetID: String) {
        guard let job = queue.first(where: { $0.request.assetID == assetID }),
              !job.isCancelling else { return }
        job.isCancelling = true
        if job.tasks.isEmpty {
            finishCancel(job)
        } else {
            for task in job.tasks.values {
                task.cancel()
            }
        }
    }

    func isDownloading(assetID: String) -> Bool {
        queue.contains { $0.request.assetID == assetID }
    }

    // MARK: - Queue

    private func enqueue(_ job: AssetDownloadJob) -> AssetDownloadJob {
        queue.append(job)
        progress[job.request.assetID] = AssetDownloadProgress(
            completedBytes: job.plan?.completedBytes ?? 0,
            totalBytes: job.plan?.totalBytes ?? 0
        )
        phases[job.request.assetID] = .queued
        return job
    }

    /// Drive the head job forward: fetch its manifest, then fill slots.
    private func pump() {
        guard isReady, let job = queue.first, !job.isCancelling else { return }
        if job.hasFreshURLs {
            fillSlots(job)
        } else if !job.isPreparing {
            job.isPreparing = true
            Task { await prepare(job) }
        }
    }

    /// Fetch the manifest and build or refresh the plan. Runs once per job.
    private func prepare(_ job: AssetDownloadJob) async {
        let request = job.request
        do {
            let manifest = try await fetchManifest(request.assetID)
            guard !job.isCancelling, queue.first === job else { return }

            var plan = job.plan ?? AssetDownloadPlan.load(from: request.directory)
            if let existing = plan, existing.version == manifest.version {
                plan = existing.refreshingURLs(from: manifest)
            } else {
                // Different version or fresh start: nothing on disk is reusable.
                for task in job.tasks.values {
                    task.cancel()
                }
                job.clearTasks()
                try? FileManager.default.removeItem(at: request.directory)
                plan = AssetDownloadPlan.make(
                    assetID: request.assetID, manifest: manifest,
                    localPath: request.localPath, chunking: chunking
                )
            }
            guard let plan else { return }

            try FileManager.default.createDirectory(
                at: request.directory, withIntermediateDirectories: true
            )
            for index in plan.files.indices where plan.isChunked(fileIndex: index) {
                let destination = request.directory.appendingPathComponent(plan.localPaths[index])
                try AssetFileWriter.preallocate(destination, size: plan.files[index].size)
            }

            job.plan = plan
            job.hasFreshURLs = true
            plan.save(in: request.directory)
            registry.add(request.directory)
            targets.register(job)
            updateProgress(job)
            fillSlots(job)
        } catch {
            // A restored job may still have tasks the daemon is running; only
            // new slots need fresh URLs. Leave them be and retry the manifest
            // on the next task event instead of killing a healthy download.
            if !job.tasks.isEmpty, !job.isCancelling {
                job.isPreparing = false
                return
            }
            fail(job, error: error)
        }
    }

    /// Start requests until `maxInFlight` are running or nothing is left.
    private func fillSlots(_ job: AssetDownloadJob) {
        guard !job.isCancelling, let plan = job.plan else { return }
        guard job.hasFreshURLs else {
            pump() // retries the manifest fetch if an earlier one failed
            return
        }

        while job.tasks.count < Self.maxInFlight, job.nextPartIndex < plan.parts.count {
            let partIndex = job.nextPartIndex
            job.nextPartIndex += 1
            let part = plan.parts[partIndex]
            if plan.completed.contains(part) || job.taskParts.values.contains(part) {
                continue
            }
            guard let url = URL(string: plan.files[part.fileIndex].url) else {
                fail(job, error: ModelAssetError.invalidURL(plan.files[part.fileIndex].path))
                return
            }
            var request = URLRequest(url: url)
            if !part.isWhole {
                request.setValue("bytes=\(part.offset)-\(part.end)", forHTTPHeaderField: "Range")
            }
            let task = session.downloadTask(with: request)
            task.taskDescription = AssetTaskTargets.key(
                assetID: job.request.assetID,
                partIndex: partIndex
            )
            job.tasks[task.taskIdentifier] = task
            job.taskParts[task.taskIdentifier] = part
            task.resume()
            phases[job.request.assetID] = .transferring
        }

        if job.tasks.isEmpty, job.nextPartIndex >= plan.parts.count, !job.isVerifying {
            verify(job)
        }
    }

    /// Whole-asset SHA-256 check, off the main actor, then mark installed.
    private func verify(_ job: AssetDownloadJob) {
        guard let plan = job.plan else { return }
        job.isVerifying = true
        phases[job.request.assetID] = .preparing
        let directory = job.request.directory
        Task {
            let mismatch = await Task.detached(priority: .userInitiated) { () -> Int? in
                for (index, file) in plan.files.enumerated() {
                    let url = directory.appendingPathComponent(plan.localPaths[index])
                    let actual = (try? ModelAssetService.sha256Hex(of: url)) ?? ""
                    if actual.caseInsensitiveCompare(file.sha256) != .orderedSame {
                        return index
                    }
                }
                return nil
            }.value

            guard queue.first === job, !job.isCancelling else { return }
            if let index = mismatch {
                let url = directory.appendingPathComponent(plan.localPaths[index])
                try? FileManager.default.removeItem(at: url)
                job.plan?.reset(fileIndex: index)
                job.plan?.save(in: directory)
                fail(job, error: ModelAssetError.checksumMismatch(path: plan.files[index].path))
                return
            }

            ModelAssetService.writeMarker(id: plan.assetID, version: plan.version, in: directory)
            AssetDownloadPlan.remove(from: directory)
            dequeue(job)
            for continuation in job.continuations {
                continuation.resume()
            }
        }
    }

    /// Stop the job and report `error`. Partial files and the sidecar stay so
    /// the next attempt resumes; the job leaves the relaunch registry so it
    /// doesn't restart on its own.
    private func fail(_ job: AssetDownloadJob, error: Error) {
        for task in job.tasks.values {
            task.cancel()
        }
        job.clearTasks()
        job.plan?.save(in: job.request.directory)
        dequeue(job)
        for continuation in job.continuations {
            continuation.resume(throwing: error)
        }
    }

    private func finishCancel(_ job: AssetDownloadJob) {
        try? FileManager.default.removeItem(at: job.request.directory)
        dequeue(job)
        for continuation in job.continuations {
            continuation.resume(throwing: CancellationError())
        }
    }

    private func dequeue(_ job: AssetDownloadJob) {
        registry.remove(job.request.directory)
        targets.unregister(assetID: job.request.assetID)
        progress.removeValue(forKey: job.request.assetID)
        phases.removeValue(forKey: job.request.assetID)
        queue.removeAll { $0 === job }
        pump()
    }

    private func updateProgress(_ job: AssetDownloadJob) {
        guard let plan = job.plan else { return }
        progress[job.request.assetID] = AssetDownloadProgress(
            completedBytes: plan.completedBytes,
            inFlightBytes: job.inFlightBytes.values.reduce(0, +),
            totalBytes: plan.totalBytes
        )
    }

    // MARK: - Relaunch

    /// Rebuild jobs for downloads the session may still be running.
    private func restoreJobs() {
        for directory in registry.directories() {
            guard let plan = AssetDownloadPlan.load(from: directory) else {
                registry.remove(directory)
                continue
            }
            let job = AssetDownloadJob(
                request: .init(assetID: plan.assetID, directory: directory)
            )
            job.plan = plan
            _ = enqueue(job)
            targets.register(job)
        }
    }

    /// Match surviving session tasks back to their jobs, then start pumping.
    private func reattach(_ tasks: [URLSessionTask]) {
        for task in tasks {
            guard let key = task.taskDescription,
                  let (assetID, partIndex) = AssetTaskTargets.parse(key),
                  let job = queue.first(where: { $0.request.assetID == assetID }),
                  let plan = job.plan, plan.parts.indices.contains(partIndex)
            else {
                task.cancel()
                continue
            }
            job.tasks[task.taskIdentifier] = task
            job.taskParts[task.taskIdentifier] = plan.parts[partIndex]
        }
        isReady = true
        pump()
    }

    // MARK: - Task events (main actor)

    /// Resolve a task's job and part from its `taskDescription`. Works for
    /// callbacks the session replays at relaunch before `getAllTasks` has
    /// rebuilt `job.tasks`, which are keyed by identifier.
    private func resolve(_ key: String?) -> (AssetDownloadJob, AssetPart)? {
        guard let key, let (assetID, partIndex) = AssetTaskTargets.parse(key),
              let job = queue.first(where: { $0.request.assetID == assetID }),
              let plan = job.plan, plan.parts.indices.contains(partIndex)
        else { return nil }
        return (job, plan.parts[partIndex])
    }

    /// A task completing (with or without error) during a cancel just drains
    /// the job; `finishCancel` runs once nothing is live.
    private func drainIfCancelling(_ job: AssetDownloadJob) -> Bool {
        guard job.isCancelling else { return false }
        if job.tasks.isEmpty { finishCancel(job) }
        return true
    }

    private func partDidFinish(taskID: Int, key: String?, result: Result<Void, Error>) {
        guard let (job, part) = resolve(key) else { return }
        job.removeTask(taskID)
        if drainIfCancelling(job) { return }
        switch result {
        case .success:
            job.plan?.completed.insert(part)
            job.plan?.save(in: job.request.directory)
            updateProgress(job)
            fillSlots(job)
        case .failure(let error):
            fail(job, error: error)
        }
    }

    private func taskDidCancel(taskID: Int, key: String?) {
        guard let (job, _) = resolve(key) else { return }
        job.removeTask(taskID)
        _ = drainIfCancelling(job)
    }

    private func taskDidFail(taskID: Int, key: String?, error: Error) {
        guard let (job, _) = resolve(key) else { return }
        job.removeTask(taskID)
        if drainIfCancelling(job) { return }
        fail(job, error: error)
    }

    private func taskDidWrite(taskID: Int, key: String?, bytes: Int64) {
        guard let (job, _) = resolve(key), job.tasks[taskID] != nil else { return }
        job.inFlightBytes[taskID] = bytes
        updateProgress(job)
    }
}

// MARK: - URLSession delegate

extension AssetDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temp file must be consumed before this returns.
        let result = targets.place(downloadTask: downloadTask, from: location)
        let taskID = downloadTask.taskIdentifier
        let key = downloadTask.taskDescription
        Task { @MainActor in partDidFinish(taskID: taskID, key: key, result: result) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskID = downloadTask.taskIdentifier
        let key = downloadTask.taskDescription
        Task { @MainActor in taskDidWrite(taskID: taskID, key: key, bytes: totalBytesWritten) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let taskID = task.taskIdentifier
        let key = task.taskDescription
        if (error as NSError).code == NSURLErrorCancelled {
            Task { @MainActor in taskDidCancel(taskID: taskID, key: key) }
        } else {
            Task { @MainActor in taskDidFail(taskID: taskID, key: key, error: error) }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            let handler = backgroundCompletionHandler
            backgroundCompletionHandler = nil
            handler?()
        }
    }
}

// MARK: - Progress observation

extension AssetDownloader {
    /// Poll an asset's progress every 250 ms and forward bytes and phase until
    /// the returned task is cancelled (or the job leaves the queue).
    func observeProgress(
        assetID: String,
        _ update: @escaping @MainActor (AssetDownloadProgress, Phase) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if let p = progress[assetID], let phase = phases[assetID] {
                    update(p, phase)
                }
            }
        }
    }
}
