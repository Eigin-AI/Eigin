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
    static let unloadTimeoutSeconds = 120

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
        if isDownloaded { state = .ready }
    }

    /// Downloads the model with progress reporting, then initializes from cache.
    func download() async {
        guard state != .ready else { return }
        state = .downloading(fractionCompleted: 0)
        do {
            // Phase 1: seed the FluidAudio cache from the self-hosted mirror.
            try await PocketTTSModelDownloader.download { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.state = .downloading(fractionCompleted: fraction)
                }
            }
            // Phase 2: initialize from cache (fast — files already on disk)
            let mgr = PocketTtsManager()
            try await mgr.initialize()
            manager = mgr
            copyBundledVoices()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Removes the model from memory, deletes cached files from disk, and resets state.
    func delete() {
        unload()
        try? FileManager.default.removeItem(at: PocketTTSModelDownloader.cacheDirectory)
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
