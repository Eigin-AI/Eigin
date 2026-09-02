#if !targetEnvironment(simulator)
import Foundation

/// Manages the Plapre Pico model lifecycle: download (with on-the-fly CoreML compilation),
/// readiness checks, and the declined-prompt flag.
///
/// Mirrors `PocketTTSModelManager` so the existing Voice Engine settings UI and
/// `OnDemandAsset` flow pick it up automatically. The in-memory load/unload of the
/// inference instance will be added in a follow-up step alongside `PlaprePicoManager`.
@Observable
@MainActor
final class PlaprePicoModelManager: OnDemandAsset, @unchecked Sendable {
    let id = "plapre-pico"
    let displayName = Localized.Voice.danishName
    let downloadDescription = Localized.Voice.danishDescription
    /// Size reported by the mirror manifest once fetched; static fallback otherwise.
    private(set) var mirrorSizeBytes: Int64?
    static let unloadTimeoutSeconds = 240

    /// Approximate mirror footprint, for rows and offers.
    var sizeDescription: String? {
        let bytes = mirrorSizeBytes ?? 570_000_000
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Smooths raw byte progress into a time-left estimate.
    private var transferEstimator = TransferRateEstimator()

    private(set) var state: AssetState = .notDownloaded
    var hasBeenDeclined: Bool {
        get { UserDefaults.standard.bool(forKey: declinedKey) }
        set { UserDefaults.standard.set(newValue, forKey: declinedKey) }
    }

    /// The loaded inference manager. Non-nil only while held in memory.
    private(set) var manager: PlaprePicoManager?
    private(set) var isLoading: Bool = false
    private var loadTask: Task<Void, Error>?
    private var unloadTask: Task<Void, Never>?
    private static let unloadDelay: Duration = .seconds(unloadTimeoutSeconds)

    private let declinedKey = "plapre-pico-declined"

    // MARK: - Availability

    var isDownloaded: Bool {
        PlaprePicoAssets.verifyOnDisk()
    }

    /// Synchronous on-disk check used at app launch to set initial state.
    func checkAvailability() {
        prewarmMirrorSize()
        if isDownloaded {
            state = .ready
        } else if AssetDownloader.shared.isDownloading(assetID: PlaprePicoAssets.assetID) {
            // Background session kept going across a relaunch — re-attach.
            Task { await download() }
        }
    }

    /// Fetch the mirror-reported size so the offer row states the real cost
    /// before the user commits.
    private func prewarmMirrorSize() {
        guard mirrorSizeBytes == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            mirrorSizeBytes = await ModelAssetService
                .totalBytes(for: PlaprePicoAssets.assetID)
        }
    }

    // MARK: - Download

    func download() async {
        guard state != .ready, !state.isBusy else { return }
        transferEstimator.reset()
        state = .queued
        do {
            let progressTask = AssetDownloader.shared.observeProgress(
                assetID: PlaprePicoAssets.assetID
            ) { [weak self] progress, phase in
                self?.recordTransfer(progress: progress, phase: phase)
            }
            defer { progressTask.cancel() }
            try await PlaprePicoAssets.downloadAll()
            state = .ready
        } catch is CancellationError {
            // A user cancel isn't a failure — the row just falls back to Offer.
            state = isDownloaded ? .ready : .notDownloaded
        } catch let error as URLError where error.code == .cancelled {
            state = isDownloaded ? .ready : .notDownloaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Fold a downloader tick into state: phase mapping plus a smoothed
    /// time-left estimate.
    private func recordTransfer(progress: AssetDownloadProgress, phase: AssetDownloader.Phase) {
        let secondsLeft = transferEstimator.estimate(
            completedBytes: progress.completedBytes,
            totalBytes: progress.totalBytes,
            now: .now
        )
        switch phase {
        case .queued:
            state = .queued
        case .transferring:
            state = .downloading(AssetTransferInfo(
                fractionCompleted: progress.fraction,
                bytesCompleted: progress.completedBytes,
                totalBytes: progress.totalBytes,
                estimatedSecondsLeft: secondsLeft
            ))
        case .preparing:
            state = .preparing(fractionCompleted: nil)
        }
    }

    func delete() {
        unload()
        // An in-flight download removes its own directory once its tasks drain.
        if AssetDownloader.shared.isDownloading(assetID: PlaprePicoAssets.assetID) {
            AssetDownloader.shared.cancel(assetID: PlaprePicoAssets.assetID)
        } else {
            PlaprePicoAssets.deleteAll()
        }
        state = .notDownloaded
    }

    func decline() {
        hasBeenDeclined = true
    }

    // MARK: - Memory lifecycle

    /// Loads the model into memory. Idempotent and concurrency-safe — same lease
    /// semantics as `PocketTTSModelManager.load()`.
    func load() async throws {
        if manager != nil {
            unloadTask?.cancel()
            unloadTask = nil
            return
        }
        if let existing = loadTask {
            try await existing.value
            return
        }

        isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.isLoading = false
                    self?.loadTask = nil
                }
            }
            let mgr = try await PlaprePicoManager.load()
            await MainActor.run { [weak self] in
                self?.manager = mgr
            }
        }
        loadTask = task
        try await task.value
    }

    func unload() {
        let wasLoaded = manager != nil
        loadTask?.cancel()
        loadTask = nil
        manager = nil
        isLoading = false
        unloadTask?.cancel()
        unloadTask = nil
        if wasLoaded {
            AppLogger.info("Plapre: unloaded", category: .general)
        }
    }

    func scheduleUnload() {
        unloadTask?.cancel()
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.unloadDelay)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.unload() }
        }
    }
}
#endif
