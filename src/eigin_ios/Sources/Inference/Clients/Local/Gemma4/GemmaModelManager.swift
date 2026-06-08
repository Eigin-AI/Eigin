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

    private(set) var state: AssetState = .notDownloaded
    /// Human-readable status during download/compile.
    private(set) var statusMessage = ""

    /// The loaded inference engine, available after ``load()``.
    private(set) var llm: GemmaRuntime?
    private(set) var isLoading = false

    private var downloadTask: Task<Void, Never>?
    private var loadTask: Task<Void, Error>?
    private let declinedKey = "coreml-gemma-declined"

    /// The model info from the CoreML-LLM library.
    private let localModelInfo = GemmaModelDownloader.ModelInfo.default

    private static let requiredRAMBytes: UInt64 = 5 * 1_073_741_824

    private let deviceInfo: any DeviceInfoService

    init(deviceInfo: any DeviceInfoService = DefaultDeviceInfoService()) {
        self.deviceInfo = deviceInfo
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

    func checkAvailability() {
        if llm != nil {
            state = .ready
        } else if isReady {
            state = .downloaded
        } else {
            state = .notDownloaded
        }
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
            state = .failed(Localized.Model.insufficientRAM)
            return
        }

        guard hasRequiredDiskSpace() else {
            let requiredGB = Double(Self.minimumRequiredFreeSpaceBytes(for: localModelInfo)) /
                1_000_000_000
            state = .failed(Localized.Model.storageNotEnough(String(format: "%.1f", requiredGB)))
            return
        }

        state = .downloading(fractionCompleted: 0)
        statusMessage = "Downloading…"

        downloadTask = Task {
            do {
                let progressTask = Task { @MainActor in
                    let downloader = GemmaModelDownloader.shared
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(250))
                        if downloader.isDownloading {
                            state = .downloading(fractionCompleted: downloader.progress)
                            statusMessage = downloader.status.isEmpty
                                ? "Downloading…"
                                : downloader.status
                        }
                    }
                }

                _ = try await GemmaModelDownloader.shared.download(localModelInfo)
                progressTask.cancel()

                try Task.checkCancellation()

                statusMessage = ""
                state = .downloaded
            } catch is CancellationError {
                statusMessage = ""
                state = .notDownloaded
            } catch {
                statusMessage = ""
                state = .failed(error.localizedDescription)
                AppLogger.error(
                    "Gemma model download failed: \(private: error.localizedDescription)",
                    category: .chat
                )
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
            state = .failed(Localized.Model.storageNotEnough(String(format: "%.1f", requiredGB)))
            return
        }

        state = .compiling(fractionCompleted: 0)
        statusMessage = "Preparing model for your device…"

        URLCache.shared.removeAllCachedResponses()

        do {
            let info = localModelInfo
            let compiled = try await GemmaRuntime.load(
                model: info,
                onChunkLoaded: { @Sendable [weak self] loaded, total in
                    Task { @MainActor [weak self] in
                        self?.state = .compiling(
                            fractionCompleted: Double(loaded) / Double(max(total, 1))
                        )
                    }
                }
            )
            compiled.reset()
            llm = compiled
            statusMessage = ""
            state = .ready
        } catch is CancellationError {
            statusMessage = ""
            state = .downloaded
        } catch {
            statusMessage = ""
            state = .failed(error.localizedDescription)
            AppLogger.error(
                "Gemma model compilation failed: \(private: error.localizedDescription)",
                category: .chat
            )
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        GemmaModelDownloader.shared.cancelDownload()
        state = .notDownloaded
    }

    func delete() {
        cancel()
        unload()
        try? GemmaModelDownloader.shared.delete(localModelInfo)
        state = .notDownloaded
    }

    func decline() {
        hasBeenDeclined = true
    }

    // MARK: - Memory lifecycle

    func load() async throws {
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
        loadTask?.cancel()
        loadTask = nil
        llm?.reset()
        llm = nil
        isLoading = false
    }
}
