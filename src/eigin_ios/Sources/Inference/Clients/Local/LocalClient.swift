import EiginSDK
import Foundation

struct LocalClient: LLMClient {
    let inference: EiginSDK.Experimental.Inference.Local
    private let modelDownloaded: @Sendable () -> Bool

    init(
        inference: EiginSDK.Experimental.Inference
            .Local = .init(prepare: GemmaLocalInference.prepare),
        modelDownloaded: @escaping @Sendable () -> Bool = { GemmaModelStore.isDownloaded }
    ) {
        self.inference = inference
        self.modelDownloaded = modelDownloaded
    }

    func fetchModels() async throws -> [String] {
        // Downloaded models remain available when idle eviction unloads the runtime.
        modelDownloaded() ? ["gemma-4-e2b"] : []
    }

    func validateAPIKey(model: String) async throws {}

    func chatCompletionStream(
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let eventStream = try await chatCompletionEventStream(
            messages: messages, model: model, tools: nil
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in eventStream {
                        if case .contentDelta(let text) = event {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Propagate abandonment downward: dropping this string stream cancels
            // its consumption of the event stream, which in turn stops generation.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func chatCompletionEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey _: String? = nil // Local models currently don't use cache keys.
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        try await chatCompletionEventStream(
            messages: messages, model: model, tools: tools,
            cacheKey: nil, inlineToolRunner: nil
        )
    }

    func chatCompletionEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey _: String? = nil,
        inlineToolRunner: InlineToolRunner?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        guard model == "gemma-4-e2b" else { throw LocalClientError.unsupportedModel }
        let execute: EiginSDK.Experimental.Inference.Local.ExecuteTool? = inlineToolRunner
            .map { runner in
                { @Sendable call in
                    let result = await runner.run(LocalInferenceSDKConversion.call(call))
                    return .init(
                        toolCallId: result.toolCallID,
                        content: result.content,
                        isError: result.isError
                    )
                }
            }
        do {
            let input = try LocalInferenceSDKConversion.input(
                messages: messages,
                model: model,
                tools: tools
            )
            let stream = try await inference.stream(input, executeTool: execute)
            return InferenceSDKStream.events(stream, mapError: LocalInferenceSDKConversion.failure)
        } catch { throw LocalInferenceSDKConversion.failure(error) }
    }
}

enum LocalClientError: LocalizedError {
    case unsupportedModel
    case modelNotLoaded
    case modelNotDownloaded
    case deviceUnsupported(detail: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedModel: Localized.Model.unsupported
        case .modelNotLoaded: Localized.Model.notLoaded
        case .modelNotDownloaded: Localized.Model.notDownloaded
        case .deviceUnsupported: Localized.Model.insufficientRAM
        }
    }
}
