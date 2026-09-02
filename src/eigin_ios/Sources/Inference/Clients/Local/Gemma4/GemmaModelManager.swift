import Foundation

/// Manages the Gemma 4 E2B model lifecycle: download, load, unload.
///
/// Fetches the `.litertlm` model file through ``AssetDownloader`` (layout in
/// ``GemmaModelStore``) and wraps ``GemmaRuntime`` (LiteRT-LM) for inference. Conforms to
/// ``OnDemandAsset``
/// for the settings download flow.
@MainActor
@Observable
final class GemmaModelManager: OnDemandAsset, @unchecked Sendable {
    static let shared = GemmaModelManager()

    let id = "litert-gemma"
    let displayName = Localized.Model.Gemma4e2b.name
    let downloadDescription = Localized.Onboarding.LocalModel.description

    /// Runtime-only states that the disk can't tell us about. Terminal states
    /// (notDownloaded / downloaded / ready) are derived from `llm` and disk
    /// in ``state`` so they stay correct without anyone having to remember to
    /// refresh them after a cold start or a lazy load from chat.
    private enum Transient: Equatable {
        case idle
        case downloading(Double)
        case preparing
        case failed(String)
    }

    private var transient: Transient = .idle

    var state: AssetState {
        switch transient {
        case .downloading(let p): .downloading(fractionCompleted: p)
        case .preparing: .compiling(fractionCompleted: 0)
        case .failed(let m): .failed(m)
        case .idle:
            if llm != nil { .ready }
            else if isReady { .downloaded }
            else { .notDownloaded }
        }
    }

    /// The loaded inference engine, available after ``load()``.
    private(set) var llm: GemmaRuntime?
    private(set) var isLoading = false

    private var downloadTask: Task<Void, Never>?
    private var loadTask: Task<Void, Error>?
    private let declinedKey = StorageKey.gemmaDeclined

    /// Minimum device RAM to run the local model. A real session — long-context
    /// conversation plus a concurrently-loaded voice model — sits around 3 GB of
    /// resident memory, so a 4 GB device (e.g. iPhone 13) would be fully consumed
    /// and jetsam-killed. The 5 GB gate keeps the 6 GB iPhone 15 in (its reported
    /// physicalMemory is comfortably above this) while screening out 4 GB
    /// devices, leaving headroom for the full workload.
    private static let requiredRAMBytes: UInt64 = 5 * 1_073_741_824

    private let deviceInfo: any DeviceInfoService

    init(deviceInfo: any DeviceInfoService = DefaultDeviceInfoService()) {
        self.deviceInfo = deviceInfo
        ModelStorage.excludeFromBackup()
        startMemoryPressureMonitor()
        resumeIfInProgress()
    }

    var hasBeenDeclined: Bool {
        get { UserDefaults.standard.bool(forKey: declinedKey) }
        set { UserDefaults.standard.set(newValue, forKey: declinedKey) }
    }

    /// Estimated download size in bytes.
    static var estimatedSize: Int64 {
        GemmaModelStore.estimatedSize
    }

    /// Multiplier applied to the estimated model size to reserve enough free
    /// space for the download plus LiteRT's compiled-graph cache. Increase if
    /// users hit storage errors during first-run preparation.
    static let storageHeadroomFactor: Double = 2.0

    /// Whether the model is fully downloaded and ready to use.
    var isReady: Bool {
        GemmaModelStore.isDownloaded
    }

    // MARK: - Device requirements

    /// Whether this device meets the minimum hardware requirements to run the local model.
    ///
    /// RAM is fixed hardware so this is safe to use as a permanent visibility gate.
    /// Disk space is dynamic and is checked separately at download time.
    var isSupported: Bool {
        hasRequiredRAM()
    }

    static var minimumRequiredFreeSpaceBytes: Int64 {
        Int64(Double(estimatedSize) * storageHeadroomFactor)
    }

    func hasRequiredDiskSpace() -> Bool {
        let required = Self.minimumRequiredFreeSpaceBytes
        guard let free = deviceInfo.freeDiskSpaceBytes() else { return false }
        return free >= required
    }

    func hasRequiredRAM() -> Bool {
        deviceInfo.physicalMemoryBytes() >= Self.requiredRAMBytes
    }

    /// JSON diagnostic describing why this device can't run the model. Surfaced
    /// as the raw payload of ``LocalClientError/deviceUnsupported(detail:)`` and
    /// rendered as a structured field card in the chat error detail sheet.
    func insufficientResourcesDetail() -> String {
        let gb = { (bytes: UInt64) in
            String(format: "%.1f", Double(bytes) / 1_073_741_824)
        }
        let payload: [String: Any] = [
            "error": [
                "type": "insufficient_memory",
                "message": Localized.Model.deviceUnsupportedSuggestion,
                "required_memory_gb": gb(Self.requiredRAMBytes),
                "device_memory_gb": gb(deviceInfo.physicalMemoryBytes()),
            ],
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        ), let json = String(data: data, encoding: .utf8) else {
            return Localized.Model.deviceUnsupportedSuggestion
        }
        return json
    }

    // MARK: - Download

    func download() async {
        guard !state.isDownloading else { return }

        guard hasRequiredRAM() else {
            transient = .failed(Localized.Model.insufficientRAM)
            return
        }

        guard hasRequiredDiskSpace() else {
            let requiredGB = Double(Self.minimumRequiredFreeSpaceBytes) / 1_000_000_000
            transient = .failed(
                Localized.Model.storageNotEnough(String(format: "%.1f", requiredGB))
            )
            return
        }

        startDownload()
    }

    /// A download the background session kept running across a relaunch has
    /// nobody awaiting it; re-attach so the UI reflects it and completion is
    /// handled. Skips the resource checks — the bytes are already committed.
    private func resumeIfInProgress() {
        guard AssetDownloader.shared.isDownloading(assetID: GemmaModelStore.assetID) else { return }
        startDownload()
    }

    private func startDownload() {
        transient = .downloading(0)

        downloadTask = Task {
            do {
                let progressTask = AssetDownloader.shared.observeProgress(
                    assetID: GemmaModelStore.assetID
                ) { [weak self] fraction in
                    self?.transient = .downloading(fraction)
                }
                defer { progressTask.cancel() }

                try await AssetDownloader.shared.download(
                    .init(assetID: GemmaModelStore.assetID, directory: GemmaModelStore.directory)
                )

                try Task.checkCancellation()

                // A freshly downloaded artifact invalidates any previously
                // compiled engine graph. LiteRT keys its cache and never evicts
                // stale entries, so clear the cache now to avoid accumulating
                // multiple GB of orphaned graphs across model updates. The next
                // load recompiles in a few seconds. The engine is not loaded on
                // the download path, so nothing holds these files.
                try? FileManager.default.removeItem(at: GemmaRuntime.engineCacheDirectory)

                transient = .idle
            } catch is CancellationError {
                transient = .idle
            } catch {
                transient = .failed(error.localizedDescription)
                AppLogger.error(
                    "Gemma model download failed: \(private: error.localizedDescription)",
                    category: .chat
                )
            }
        }
    }

    // MARK: - Prepare

    /// Initialize the LiteRT engine for the downloaded model. Triggered when the
    /// model lands on disk; completes in seconds (LiteRT caches its compiled
    /// graph under the engine's `cacheDir`).
    func compile() async {
        guard state == .downloaded else { return }

        transient = .preparing
        do {
            let runtime = try await loadRuntime()
            runtime.reset()
            llm = runtime
            transient = .idle
        } catch is CancellationError {
            transient = .idle
        } catch {
            transient = .failed(error.localizedDescription)
            AppLogger.error(
                "Gemma model preparation failed: \(private: error.localizedDescription)",
                category: .chat
            )
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        AssetDownloader.shared.cancel(assetID: GemmaModelStore.assetID)
        transient = .idle
    }

    func delete() {
        // An in-flight download removes its own directory once its tasks drain.
        let wasDownloading = AssetDownloader.shared.isDownloading(assetID: GemmaModelStore.assetID)
        cancel()
        unload()
        if !wasDownloading {
            try? GemmaModelStore.delete()
        }
        // LiteRT never prunes its compiled-graph cache (multiple GB). Clear it
        // here so deleting the model actually reclaims the space rather than
        // orphaning the cache in Library/Caches. The engine is unloaded above,
        // so no live handle holds these files.
        try? FileManager.default.removeItem(at: GemmaRuntime.engineCacheDirectory)
        transient = .idle
    }

    func decline() {
        hasBeenDeclined = true
    }

    // MARK: - Memory lifecycle

    func load() async throws {
        // Any (re)load is activity — stop a pending idle eviction from firing
        // while we bring the engine back up.
        idleEvictionTask?.cancel()
        idleEvictionTask = nil

        if state == .downloaded {
            await compile()
            if llm == nil { throw LocalClientError.modelNotLoaded }
            return
        }
        if llm != nil { return }
        if let existing = loadTask {
            try await existing.value
            return
        }

        AppLogger.info("GemmaRuntime: starting LiteRT model load", category: .chat)
        isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.isLoading = false
                    self?.loadTask = nil
                }
            }

            let start = ContinuousClock.now
            let loaded = try await loadRuntime()
            let loadMs = start.duration(to: .now).milliseconds
            AppLogger.info(
                "GemmaRuntime: model loaded in \(public: loadMs)ms — \(public: loaded.modelName), \(public: loaded.contextLength) ctx",
                category: .chat
            )

            await MainActor.run { [weak self] in
                self?.llm = loaded
            }
        }
        loadTask = task
        try await task.value
    }

    func unload() {
        idleEvictionTask?.cancel()
        idleEvictionTask = nil
        loadTask?.cancel()
        loadTask = nil
        llm?.reset()
        llm = nil
        isLoading = false
    }

    // MARK: - Idle eviction

    /// Idle period after which the engine is fully unloaded so its weights and KV
    /// cache stop occupying memory while the user is away. Any generation resets
    /// this, so an active chat or live call keeps the model resident.
    private static let idleUnloadSeconds = 90

    /// Number of generations currently running or queued against the engine.
    /// The engine is only evicted while this is zero.
    private var activeGenerationCount = 0
    private var idleEvictionTask: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// Mark the start of a generation so idle eviction can't unload the engine
    /// underneath it. Always pair with ``endGeneration()``.
    func beginGeneration() {
        activeGenerationCount += 1
        idleEvictionTask?.cancel()
        idleEvictionTask = nil
    }

    /// Mark the end of a generation; once nothing else is running, arm the idle
    /// timer that unloads the engine.
    func endGeneration() {
        activeGenerationCount = max(0, activeGenerationCount - 1)
        guard activeGenerationCount == 0 else { return }
        scheduleIdleEviction()
    }

    private func scheduleIdleEviction() {
        idleEvictionTask?.cancel()
        idleEvictionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleUnloadSeconds))
            guard let self, !Task.isCancelled else { return }
            guard activeGenerationCount == 0, llm != nil else { return }
            AppLogger.info(
                "Gemma: idle for \(public: Self.idleUnloadSeconds)s — unloading engine",
                category: .chat
            )
            unload()
        }
    }

    /// Unload immediately on system memory pressure (when nothing is running).
    private func startMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.activeGenerationCount == 0, self.llm != nil else { return }
                AppLogger.warning("Gemma: memory pressure — unloading engine", category: .chat)
                self.unload()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: - Runtime construction

    /// Build a ``GemmaRuntime`` for the downloaded `.litertlm` file, sized to the
    /// catalog's context window (the single source of truth feeding
    /// `EngineConfig.maxNumTokens`).
    private func loadRuntime() async throws -> GemmaRuntime {
        guard let modelURL = GemmaModelStore.modelURL else {
            throw LocalClientError.modelNotLoaded
        }
        let contextWindow = KnownModelCatalog.lookup("gemma-4-e2b")?.contextWindow ?? 8192
        return try await GemmaRuntime.load(modelPath: modelURL, contextWindow: contextWindow)
    }
}
