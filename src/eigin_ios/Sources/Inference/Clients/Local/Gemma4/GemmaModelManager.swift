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
    let displayName = "Gemma 4"

    var downloadDescription: String {
        "Gemma 4 E2B on-device model (~2.8 GB download, ~1 GB memory). Supports Danish."
    }

    internal(set) var state: AssetState = .notDownloaded
    /// Human-readable status during download/compile.
    private(set) var statusMessage = ""

    /// The loaded inference engine, available after ``load()``.
    private(set) var llm: GemmaRuntime?
    private(set) var isLoading = false

    private var downloadTask: Task<Void, Never>?
    private var loadTask: Task<Void, Error>?
    private let declinedKey = "coreml-gemma-declined"

    /// The model info from the CoreML-LLM library.
    private var modelInfo: GemmaModelDownloader.ModelInfo {
        GemmaModelDownloader.ModelInfo.defaults[0] // Gemma 4 E2B
    }

    var hasBeenDeclined: Bool {
        get { UserDefaults.standard.bool(forKey: declinedKey) }
        set { UserDefaults.standard.set(newValue, forKey: declinedKey) }
    }

    /// Estimated download size in bytes (~2.8 GB).
    static let estimatedSize: Int64 = 2_800_000_000

    /// Whether the model is fully downloaded and ready to use.
    var isReady: Bool {
        GemmaModelDownloader.shared.isDownloaded(modelInfo)
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

    // MARK: - Download

    func download() async {
        guard !state.isDownloading else { return }
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

                _ = try await GemmaModelDownloader.shared.download(modelInfo)
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
        guard isReady, llm == nil, !state.isCompiling else { return }
        state = .compiling(fractionCompleted: 0)
        statusMessage = "Preparing model for your device…"

        URLCache.shared.removeAllCachedResponses()

        do {
            let info = modelInfo
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

    /// Triggers compilation if the model is downloaded, not loaded, and the
    /// app is in the foreground. Called from `ContentView` on every
    /// foreground so the model has a chance to be ready before the user
    /// starts a conversation.
    func tryAutoCompile(isActive: Bool) {
        guard isActive else { return }
        guard isReady, llm == nil, !state.isCompiling else { return }
        Task { await compile() }
    }

    func delete() {
        cancel()
        unload()
        try? GemmaModelDownloader.shared.delete(modelInfo)
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
        let info = modelInfo
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
