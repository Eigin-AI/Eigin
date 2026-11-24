import Foundation
@preconcurrency import LiteRTLM

/// Platform resource checks and native generation used by the Gemma adapter.
@MainActor
protocol GemmaInferenceHost: Sendable {
    var inferenceDownloaded: Bool { get }
    var inferenceLoaded: Bool { get }
    func hasRequiredRAM() -> Bool
    func insufficientResourcesDetail() -> String
    func load() async throws
    func beginGeneration()
    func endGeneration()
    func generate(
        _ messages: [GemmaRuntime.Message], tools: BridgedToolBox, runner: InlineToolRunner?
    ) async throws -> AsyncStream<String>
}

extension GemmaModelManager: GemmaInferenceHost {
    var inferenceDownloaded: Bool {
        state != .notDownloaded
    }

    var inferenceLoaded: Bool {
        llm != nil
    }

    func generate(
        _ messages: [GemmaRuntime.Message], tools: BridgedToolBox, runner: InlineToolRunner?
    ) async throws -> AsyncStream<String> {
        guard let llm else { throw LocalClientError.modelNotLoaded }
        return try await llm.stream(messages, tools: tools.tools, inlineToolRunner: runner)
    }
}
