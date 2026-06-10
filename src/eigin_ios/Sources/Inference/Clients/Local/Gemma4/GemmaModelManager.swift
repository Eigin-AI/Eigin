import Foundation

/// Manages the Gemma 4 E2B CoreML model lifecycle: download, load, unload.
///
/// Wraps ``ModelDownloader`` from the CoreML-LLM package for download
/// and ``GemmaRuntime`` for inference. Conforms to ``OnDemandAsset`` for
/// the settings download flow.
@MainActor
@Observable
final class GemmaModelManager: OnDemandAsset, @unchecked Sendable {
    static let shared = GemmaModelManager()

    let id = "coreml-gemma"
    let displayName = Localized.Model.Gemma4e2b.name
    let downloadDescription = Localized.Onboarding.LocalModel.description

    /// Runtime-only states that the disk can't tell us about. Terminal states
    /// (notDownloaded / downloaded / ready) are derived from `llm` and disk
    /// in ``state`` so they stay correct without anyone having to remember to
    /// refresh them after a cold start or a lazy load from chat.
    private enum Transient: Equatable {
        case idle
        case downloading(Double)
        case compiling(Double)
        case failed(String)
    }

    private var transient: Transient = .idle

    var state: AssetState {
        switch transient {
        case .downloading(let p): .downloading(fractionCompleted: p)
        case .compiling(let p): .compiling(fractionCompleted: p)
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
    private var prewarmTask: Task<Void, Never>?
    private let declinedKey = StorageKey.gemmaDeclined

    /// The model info from the CoreML-LLM library.
    private let localModelInfo = GemmaModelDownloader.ModelInfo.default

    private static let requiredRAMBytes: UInt64 = 5 * 1_073_741_824

    private let deviceInfo: any DeviceInfoService
    /// Injected so tests can replace the real `GemmaRuntime.prewarm` call.
    let prewarmRunner: @Sendable (URL, @escaping @Sendable (Int, Int) -> Void) async throws -> Void

    init(
        deviceInfo: any DeviceInfoService = DefaultDeviceInfoService(),
        prewarmRunner: (@Sendable (URL, @escaping @Sendable (Int, Int) -> Void) async throws
            -> Void)? = nil
    ) {
        self.deviceInfo = deviceInfo
        self.prewarmRunner = prewarmRunner ?? { dir, progress in
            try await GemmaRuntime.prewarm(from: dir, onProgress: progress)
        }
    }

    var hasBeenDeclined: Bool {
        get { UserDefaults.standard.bool(forKey: declinedKey) }
        set { UserDefaults.standard.set(newValue, forKey: declinedKey) }
    }

    /// Estimated download size in bytes, derived from the manifest.
    static var estimatedSize: Int64 {
        GemmaModelDownloader.expectedFileSizeBytes(for: GemmaModelDownloader.ModelInfo.default)
    }

    /// Multiplier applied to the estimated model size to reserve enough free
    /// space for both downloading and ANE compilation. Increase if users hit
    /// storage errors during first-run preparation.
    static let storageHeadroomFactor: Double = 2.0

    /// Whether the model is fully downloaded and ready to use.
    var isReady: Bool {
        GemmaModelDownloader.shared.isDownloaded(localModelInfo)
    }

    // MARK: - Device requirements

    static func minimumRequiredFreeSpaceBytes(
        for model: GemmaModelDownloader.ModelInfo
    ) -> Int64 {
        let base = GemmaModelDownloader.expectedFileSizeBytes(for: model)
        return Int64(Double(base) * storageHeadroomFactor)
    }

    func hasRequiredDiskSpace() -> Bool {
        let required = Self.minimumRequiredFreeSpaceBytes(for: localModelInfo)
        guard let free = deviceInfo.freeDiskSpaceBytes() else { return false }
        return free >= required
    }

    func hasRequiredRAM() -> Bool {
        deviceInfo.physicalMemoryBytes() >= Self.requiredRAMBytes
    }

    // MARK: - Download

    func download() async {
        guard !state.isDownloading else { return }

        guard hasRequiredRAM() else {
            transient = .failed(Localized.Model.insufficientRAM)
            return
        }

        guard hasRequiredDiskSpace() else {
            let requiredGB = Double(Self.minimumRequiredFreeSpaceBytes(for: localModelInfo)) /
                1_000_000_000
            transient = .failed(
                Localized.Model.storageNotEnough(String(format: "%.1f", requiredGB))
            )
            return
        }

        transient = .downloading(0)

        downloadTask = Task {
            do {
                let progressTask = Task { @MainActor in
                    let downloader = GemmaModelDownloader.shared
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(250))
                        if downloader.isDownloading {
                            transient = .downloading(downloader.progress)
                        }
                    }
                }

                _ = try await GemmaModelDownloader.shared.download(localModelInfo)
                progressTask.cancel()

                try Task.checkCancellation()

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

    // MARK: - Prewarm

    /// Trigger a low-memory ANE specialisation pass if the running app version
    /// has not yet been warmed.
    ///
    /// Safe to call on every foreground activation — the version guard ensures
    /// it runs at most once per build. The pass releases each chunk immediately
    /// after specialisation, so peak memory stays ≈ one chunk (~500 MB) rather
    /// than the full ~4 GB a real load would require.
    func prewarmIfNeeded() {
        // Version guard: skip if this build has already been fully warmed.
        let currentVersion = deviceInfo.appBuildVersion()
        let warmedVersion = UserDefaults.standard
            .string(forKey: StorageKey.gemmaPrewarmedBuild) ?? ""
        guard currentVersion != warmedVersion else { return }

        // State guards: must be downloaded, idle, and not in use.
        guard isReady,
              llm == nil,
              loadTask == nil,
              prewarmTask == nil,
              !state.isDownloading,
              !state.isCompiling
        else { return }

        guard let modelDir = GemmaModelDownloader.shared.localModelURL(for: localModelInfo)?
            .deletingLastPathComponent()
        else { return }

        transient = .compiling(0)

        let totalChunks = GemmaModelLayout.entries(in: modelDir).count

        prewarmTask = Task {
            do {
                try await prewarmRunner(modelDir) { @Sendable [weak self] done, _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        transient = .compiling(
                            Double(done) / Double(max(totalChunks, 1))
                        )
                    }
                }
                // Mark this build as fully warmed.
                UserDefaults.standard.set(
                    currentVersion,
                    forKey: StorageKey.gemmaPrewarmedBuild
                )
                AppLogger.info(
                    "GemmaRuntime: prewarm complete for build \(public: currentVersion)",
                    category: .chat
                )
            } catch is CancellationError {
                // Interrupted by backgrounding or user action — will retry next foreground.
            } catch {
                AppLogger.error(
                    "GemmaRuntime: prewarm failed: \(private: error.localizedDescription)",
                    category: .chat
                )
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                prewarmTask = nil
                transient = .idle
            }
        }
    }

    // MARK: - Compile

    /// Load and ANE-compile the downloaded model. First run takes 1-2 minutes;
    /// subsequent runs use CoreML's cached compilation and complete in seconds.
    func compile() async {
        guard state == .downloaded else { return }

        let modelSize = GemmaModelDownloader.expectedFileSizeBytes(for: localModelInfo)
        guard let freeSpace = deviceInfo.freeDiskSpaceBytes(), freeSpace >= modelSize else {
            let requiredGB = Double(modelSize) / 1_000_000_000
            transient = .failed(
                Localized.Model.storageNotEnough(String(format: "%.1f", requiredGB))
            )
            return
        }

        transient = .compiling(0)

        URLCache.shared.removeAllCachedResponses()

        do {
            let info = localModelInfo
            let compiled = try await GemmaRuntime.load(
                model: info,
                onChunkLoaded: { @Sendable [weak self] loaded, total in
                    Task { @MainActor [weak self] in
                        self?.transient = .compiling(
                            Double(loaded) / Double(max(total, 1))
                        )
                    }
                }
            )
            compiled.reset()
            llm = compiled
            transient = .idle
        } catch is CancellationError {
            transient = .idle
        } catch {
            transient = .failed(error.localizedDescription)
            AppLogger.error(
                "Gemma model compilation failed: \(private: error.localizedDescription)",
                category: .chat
            )
        }
    }

    /// Cancel only the prewarm pass. Called when the app moves to the background;
    /// the pass will resume on the next foreground activation.
    func cancelPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = nil
        if case .compiling = transient {
            transient = .idle
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        prewarmTask?.cancel()
        prewarmTask = nil
        GemmaModelDownloader.shared.cancelDownload()
        transient = .idle
    }

    func delete() {
        cancel()
        unload()
        try? GemmaModelDownloader.shared.delete(localModelInfo)
        transient = .idle
    }

    func decline() {
        hasBeenDeclined = true
    }

    // MARK: - Memory lifecycle

    func load() async throws {
        // If a prewarm is in flight, wait for it to finish. The model will then
        // be cached and the real load below completes in seconds.
        if let warmTask = prewarmTask {
            await warmTask.value
        }

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

        AppLogger.info(
            "GemmaRuntime: Starting model load (includes CoreML device-specific compilation on first run after rebuild)",
            category: .chat
        )
        isLoading = true
        let info = localModelInfo
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.isLoading = false
                    self?.loadTask = nil
                }
            }

            let start = ContinuousClock.now
            let loaded = try await GemmaRuntime.load(model: info)
            let loadMs = start.duration(to: .now).components.seconds * 1000
                + Int64(start.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
            AppLogger.info(
                "GemmaRuntime: Model loaded in \(public: loadMs)ms — \(public: loaded.modelName), \(public: loaded.contextLength) ctx",
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
        prewarmTask?.cancel()
        prewarmTask = nil
        loadTask?.cancel()
        loadTask = nil
        llm?.reset()
        llm = nil
        isLoading = false
    }
}
