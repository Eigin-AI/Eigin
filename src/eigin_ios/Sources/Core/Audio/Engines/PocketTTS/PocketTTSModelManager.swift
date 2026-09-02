#if !targetEnvironment(simulator)
import FluidAudio
import Foundation

/// Manages the Pocket TTS model lifecycle: download, lazy load into memory, and auto-unload.
///
/// ### State model
/// - **Not downloaded**: model files absent from disk. `isDownloaded = false`, `manager = nil`.
/// - **Downloaded, not loaded**: files on disk but `manager == nil` to save ~1 GB of RAM.
/// - **Loading**: `load()` called, `isLoading = true` until `manager` is set.
/// - **Loaded**: `manager != nil`. `scheduleUnload()` starts an inactivity timer.
///
/// ### Lease semantics
/// Calling `load()` while the manager is already in memory cancels any pending unload and
/// returns immediately — no re-initialisation. Calling `scheduleUnload()` starts the timer;
/// any subsequent `load()` before it fires cancels it and extends the lease.
@Observable
@MainActor
final class PocketTTSModelManager: OnDemandAsset, @unchecked Sendable {
    let id = "pocket-tts"
    let displayName = Localized.Voice.enhancedName
    let downloadDescription = Localized.Voice.enhancedDescription
    /// Size reported by the mirror manifest once fetched; static fallback otherwise.
    private(set) var mirrorSizeBytes: Int64?
    static let unloadTimeoutSeconds = 120

    /// Approximate mirror footprint, for rows and offers.
    var sizeDescription: String? {
        let bytes = mirrorSizeBytes ?? 100_000_000
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Smooths raw byte progress into a time-left estimate.
    private var transferEstimator = TransferRateEstimator()

    private(set) var state: AssetState = .notDownloaded
    var hasBeenDeclined: Bool {
        get { UserDefaults.standard.bool(forKey: declinedKey) }
        set { UserDefaults.standard.set(newValue, forKey: declinedKey) }
    }

    /// The initialized manager, non-nil only while loaded in memory.
    private(set) var manager: PocketTtsManager?

    /// True while `load()` is initializing the model into memory.
    private(set) var isLoading: Bool = false

    private let declinedKey = "pocket-tts-declined"

    /// In-flight load task. Concurrent callers join this rather than starting a second init.
    private var loadTask: Task<Void, Error>?
    private var unloadTask: Task<Void, Never>?

    private static let unloadDelay: Duration = .seconds(unloadTimeoutSeconds)

    // MARK: - Download detection

    /// True when all required model files are present on disk.
    /// Checks every file FluidAudio needs so a partial download isn't mistaken for ready.
    var isDownloaded: Bool {
        PocketTTSModelDownloader.isDownloaded()
    }

    // MARK: - Lifecycle

    /// Checks disk for model files and sets state accordingly. Synchronous — no I/O.
    func checkAvailability() {
        prewarmMirrorSize()
        if isDownloaded {
            state = .ready
        } else if AssetDownloader.shared.isDownloading(assetID: PocketTTSModelDownloader.assetID) {
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
                .totalBytes(for: PocketTTSModelDownloader.assetID)
        }
    }

    /// Downloads the model with progress reporting, then initializes from cache.
    func download() async {
        guard state != .ready, !state.isBusy else { return }
        transferEstimator.reset()
        state = .queued
        do {
            // Phase 1: seed the FluidAudio cache from the self-hosted mirror.
            let progressTask = AssetDownloader.shared.observeProgress(
                assetID: PocketTTSModelDownloader.assetID
            ) { [weak self] progress, phase in
                self?.recordTransfer(progress: progress, phase: phase)
            }
            defer { progressTask.cancel() }
            try await PocketTTSModelDownloader.download()
            // Phase 2: initialize from cache (seconds — files already on disk)
            state = .preparing(fractionCompleted: nil)
            let mgr = PocketTtsManager()
            try await mgr.initialize()
            manager = mgr
            copyBundledVoices()
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

    /// Removes the model from memory, deletes cached files from disk, and resets state.
    func delete() {
        unload()
        // An in-flight download removes its own directory once its tasks drain.
        if AssetDownloader.shared.isDownloading(assetID: PocketTTSModelDownloader.assetID) {
            AssetDownloader.shared.cancel(assetID: PocketTTSModelDownloader.assetID)
        } else {
            try? FileManager.default.removeItem(at: PocketTTSModelDownloader.cacheDirectory)
        }
        state = .notDownloaded
    }

    func decline() {
        hasBeenDeclined = true
    }

    // MARK: - Memory lifecycle

    /// Loads the model into memory. Idempotent and concurrency-safe:
    /// - If already loaded: cancels pending unload and returns immediately.
    /// - If a load is in flight: joins that task (no second init).
    /// - Otherwise: initialises and sets `manager`.
    func load() async throws {
        if manager != nil {
            // Already loaded — just extend the lease.
            unloadTask?.cancel()
            unloadTask = nil
            return
        }
        if let existing = loadTask {
            // Another caller is already loading — join it.
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
            let mgr = PocketTtsManager()
            try await mgr.initialize()
            await MainActor.run { [weak self] in
                self?.copyBundledVoices()
                self?.manager = mgr
            }
        }
        loadTask = task
        try await task.value
    }

    /// Releases the model from memory. State remains `.ready` — disk files are intact.
    func unload() {
        loadTask?.cancel()
        loadTask = nil
        manager = nil
        isLoading = false
        unloadTask?.cancel()
        unloadTask = nil
    }

    // MARK: - Bundled voices

    /// Copies any `*_audio_prompt.bin` files bundled in the app into the FluidAudio
    /// constants_bin cache directory. Safe to call multiple times — skips files already present.
    private func copyBundledVoices() {
        let fm = FileManager.default
        let constantsBinDir =
            PocketTTSModelDownloader.cacheDirectory
                .appendingPathComponent("constants_bin")

        guard fm.fileExists(atPath: constantsBinDir.path),
              let bundleResourceURL = Bundle.main.resourceURL
        else { return }

        // Walk the entire bundle resource tree so voices in subdirectories are found.
        let enumerator = fm.enumerator(at: bundleResourceURL, includingPropertiesForKeys: nil)
        while let src = enumerator?.nextObject() as? URL {
            guard src.pathExtension == "bin",
                  src.lastPathComponent.hasSuffix("_audio_prompt.bin")
            else { continue }
            let dest = constantsBinDir.appendingPathComponent(src.lastPathComponent)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            try? fm.copyItem(at: src, to: dest)
        }
    }

    /// Starts the inactivity timer. After some time of no `load()` calls, `unload()` is called.
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
