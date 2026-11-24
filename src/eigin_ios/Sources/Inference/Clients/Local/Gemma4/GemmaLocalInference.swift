import EiginSDK
import Foundation
@preconcurrency import LiteRTLM

/// Platform-owned Gemma loading and accelerated execution behind the SDK capability.
enum GemmaLocalInference {
    typealias SDK = EiginSDK.Experimental.Inference
    static func prepare(_ input: SDK.Input, tools handler: SDK.LocalTools?) async throws -> SDK
        .LocalSession
    {
        try await prepare(input, tools: handler, host: GemmaModelManager.shared)
    }

    static func prepare(
        _ input: SDK.Input, tools handler: SDK.LocalTools?, host manager: any GemmaInferenceHost
    ) async throws -> SDK.LocalSession {
        guard input.model == "gemma-4-e2b" else {
            throw SDK.Failure.LocalUnavailable(
                code: "unsupported_model",
                reason: Localized.Model.unsupported
            )
        }
        let tools = input.tools
        let inlineToolRunner = handler.map { handler in
            InlineToolRunner { call in
                do {
                    let result = try await handler
                        .execute(call: LocalInferenceSDKConversion.call(call))
                    return ToolResult(
                        toolCallID: result.toolCallId,
                        content: result.content,
                        isError: result.isError
                    )
                } catch {
                    return ToolResult(toolCallID: call.id, content: "{}", isError: true)
                }
            }
        }

        // Refuse before loading: insufficient RAM can cause an uncatchable jetsam kill.
        guard await manager.hasRequiredRAM() else {
            throw await SDK.Failure.LocalUnavailable(
                code: "device_unsupported",
                reason: manager.insufficientResourcesDetail()
            )
        }

        // Check downloaded files before attempting runtime initialization.
        if await !manager.inferenceDownloaded {
            throw SDK.Failure.LocalUnavailable(
                code: "not_downloaded",
                reason: Localized.Model.notDownloaded
            )
        }

        if await !manager.inferenceLoaded {
            try await manager.load()
        }
        guard await manager.inferenceLoaded else {
            throw SDK.Failure.LocalUnavailable(
                code: "not_loaded",
                reason: Localized.Model.notLoaded
            )
        }

        let libraryMessages = LocalClient.convertMessages(input.messages)

        AppLogger.debug(
            "Gemma: gemmaEventStream tools=\(public: tools?.map(\.name) ?? [])",
            category: .chat
        )

        // LiteRT invokes bridged tools through the runner held by the active session.
        let bridgedTools: [any LiteRTLM.Tool] = {
            guard let defs = tools, !defs.isEmpty, inlineToolRunner != nil else { return [] }
            return LocalClient.makeBridgedTools(defs)
        }()
        let toolBox = BridgedToolBox(bridgedTools)

        let (stream, continuation) = AsyncThrowingStream<SDK.Event, Error>.makeStream()
        let task = Task {
            await manager.beginGeneration()
            defer { Task { @MainActor in manager.endGeneration() } }
            do {
                let generationStart = ContinuousClock.now
                let metrics = GemmaStreamMetrics()

                let tokenStream = try await manager.generate(
                    libraryMessages,
                    tools: toolBox,
                    runner: inlineToolRunner
                )

                for await token in tokenStream {
                    metrics.record(token)
                    continuation.yield(.contentDelta(text: token))
                }

                continuation.yield(.finished(reason: .stop))
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
        continuation.onTermination = { _ in task.cancel() }
        let reader = GemmaEventReader(stream)
        return SDK.LocalSession(next: { try await reader.next() }, cancel: { task.cancel() })
    }
}

/// Mutable metrics accumulator. A class (reference type) lets it be shared
/// across generation timing calls without `inout` issues.
private final class GemmaStreamMetrics: @unchecked Sendable {
    var firstChunkTime: ContinuousClock.Instant?
    var chunkCount = 0

    func record(_: String) {
        if firstChunkTime == nil { firstChunkTime = .now }
        chunkCount += 1
    }
}

/// The SDK guarantees one pending read; the iterator stays isolated to this request.
private actor GemmaEventReader {
    private var iterator: AsyncThrowingStream<EiginSDK.Experimental.Inference.Event, Error>.Iterator
    init(_ stream: AsyncThrowingStream<EiginSDK.Experimental.Inference.Event, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> EiginSDK.Experimental.Inference.Event? {
        var current = iterator
        let value = try await current.next(isolation: self)
        iterator = current
        return value
    }
}
