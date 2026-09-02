import Foundation
@preconcurrency import LiteRTLM

extension LocalClient {
    static func gemmaStatus() async -> LocalModelStatus {
        let state = await GemmaModelManager.shared.state
        switch state {
        case .notDownloaded:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .notDownloaded
            )
        case .downloading(let info):
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .downloading(progress: info.fractionCompleted)
            )
        case .queued:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .downloading(progress: 0)
            )
        case .downloaded, .preparing:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .downloading(progress: 1.0)
            )
        case .ready:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .ready
            )
        case .failed(let message):
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .unavailable(reason: message)
            )
        case .unavailable(let reason):
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .unavailable(reason: reason)
            )
        }
    }

    static func allLocalModelStatuses() async -> [LocalModelStatus] {
        var statuses = [LocalModelStatus]()
        await statuses.append(appleFoundationModelStatus())
        await statuses.append(gemmaStatus())
        return statuses
    }

    func gemmaEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        inlineToolRunner: InlineToolRunner? = nil
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let manager = await GemmaModelManager.shared

        // Gate before any load. Devices below the RAM bar OOM-crash on load — a
        // jetsam kill that can't be caught — so we must refuse up front and let
        // this surface as a chat error.
        guard await manager.hasRequiredRAM() else {
            throw await LocalClientError.deviceUnsupported(
                detail: manager.insufficientResourcesDetail()
            )
        }

        // The model files must be on disk before we attempt to load. After the
        // LiteRT migration an existing on-device provider points at a model that
        // was evicted, so this is the common path for upgrading users — surface
        // a distinct, actionable error rather than a generic "not loaded".
        if await manager.state == .notDownloaded {
            throw LocalClientError.modelNotDownloaded
        }

        if await manager.llm == nil {
            try await manager.load()
        }
        guard let llm = await manager.llm else {
            throw LocalClientError.modelNotLoaded
        }

        let libraryMessages = Self.convertMessages(messages, tools: tools)

        AppLogger.debug(
            "Gemma: gemmaEventStream tools=\(public: tools?.map(\.function.name) ?? [])",
            category: .chat
        )

        // Bridge the requested tools. LiteRT owns the tool-call loop: it calls
        // each bridged tool's run() inline and feeds the result back into the
        // same session. run() reaches the real executor via the runner the
        // runtime publishes on GemmaToolBridgeRunner inside its gated span.
        let bridgedTools: [any LiteRTLM.Tool] = {
            guard let defs = tools, !defs.isEmpty, inlineToolRunner != nil else { return [] }
            return Self.makeBridgedTools(defs)
        }()
        let toolBox = BridgedToolBox(bridgedTools)

        return AsyncThrowingStream { continuation in
            let task = Task {
                await manager.beginGeneration()
                defer { Task { @MainActor in manager.endGeneration() } }
                do {
                    let generationStart = ContinuousClock.now
                    let metrics = GemmaStreamMetrics()

                    // GemmaRuntime keeps a single sendMessageStream open for the
                    // whole turn — tool rounds happen invisibly inside it. We
                    // simply forward text chunks; the stream ends only when the
                    // model stops. The runner is published inside the runtime's
                    // gated span so a concurrent stream can't clobber it.
                    let tokenStream = try await llm.stream(
                        libraryMessages,
                        tools: toolBox.tools,
                        inlineToolRunner: inlineToolRunner
                    )

                    for await token in tokenStream {
                        metrics.record(token)
                        continuation.yield(.contentDelta(token))
                    }

                    continuation.yield(.finished(.stop))
                    let totalMs = generationStart.duration(to: .now).milliseconds
                    let decodeMs = metrics.firstChunkTime.map {
                        $0.duration(to: .now).milliseconds
                    } ?? totalMs
                    let chunksPerSec = decodeMs > 0
                        ? String(
                            format: "%.1f",
                            Double(metrics.chunkCount) / (Double(decodeMs) / 1000)
                        )
                        : "–"
                    AppLogger.info(
                        "Gemma: \(public: metrics.chunkCount) chunks, \(public: decodeMs)ms (\(public: chunksPerSec) chunks/s)",
                        category: .chat
                    )

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

/// Mutable metrics accumulator. A class (reference type) lets it be shared
/// across concurrent tasks inside `gemmaEventStream` without `inout` issues.
private final class GemmaStreamMetrics: @unchecked Sendable {
    var firstChunkTime: ContinuousClock.Instant?
    var chunkCount = 0

    func record(_: String) {
        if firstChunkTime == nil { firstChunkTime = .now }
        chunkCount += 1
    }
}
