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
    static let unloadTimeoutSeconds = 240

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
        if isDownloaded { state = .ready }
    }

    // MARK: - Download

    func download() async {
        guard state != .ready else { return }
        state = .downloading(fractionCompleted: 0)
        do {
            try await PlaprePicoAssets.downloadAll { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.state = .downloading(fractionCompleted: fraction)
                }
            }
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func delete() {
        unload()
        PlaprePicoAssets.deleteAll()
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
