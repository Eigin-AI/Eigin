import Foundation

/// In-flight state for one asset download. Owned by `AssetDownloader`.
@MainActor
final class AssetDownloadJob {
    /// Restored jobs start with a bare request; the first real caller's
    /// request (with its path mapping) replaces it. See `AssetDownloader.download`.
    var request: AssetDownloadRequest
    /// Nil until the manifest has been fetched (or restored from the sidecar).
    var plan: AssetDownloadPlan?
    /// Callers awaiting completion; several can join the same job.
    var continuations: [CheckedContinuation<Void, Error>] = []

    /// Next index into `plan.parts` to dispatch.
    var nextPartIndex = 0
    /// Running session tasks by `taskIdentifier`.
    var tasks: [Int: URLSessionTask] = [:]
    var taskParts: [Int: AssetPart] = [:]
    var inFlightBytes: [Int: Int64] = [:]

    var isPreparing = false
    /// Presigned URLs in `plan` came from this launch's manifest fetch.
    var hasFreshURLs = false
    var isVerifying = false
    var isCancelling = false

    init(request: AssetDownloadRequest) {
        self.request = request
    }

    func removeTask(_ id: Int) {
        tasks.removeValue(forKey: id)
        taskParts.removeValue(forKey: id)
        inFlightBytes.removeValue(forKey: id)
    }

    func clearTasks() {
        tasks.removeAll()
        taskParts.removeAll()
        inFlightBytes.removeAll()
    }
}
