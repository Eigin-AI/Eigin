import Foundation

/// Common interface for LLM provider clients.
///
/// ``OpenAICompatibleClient`` and ``AnthropicClient`` both conform to this protocol.
/// Use ``LLMClientFactory`` to create the right client for a given base URL.
protocol LLMClient: Sendable {
    func fetchModels() async throws -> [String]
    func validateAPIKey(model: String) async throws
    func chatCompletionStream(messages: [ChatMessage], model: String) async throws
        -> AsyncThrowingStream<String, Error>
    func chatCompletionEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?
    ) async throws
        -> AsyncThrowingStream<ChatStreamEvent, Error>
}

/// Creates the appropriate ``LLMClient`` based on the provider's base URL.
enum LLMClientFactory {
    static func client(baseURL: String, apiToken: String) -> LLMClient {
        if ProviderPreset.isLocal(baseURL) {
            return LocalClient()
        }
        if baseURL.contains("api.anthropic.com") {
            return AnthropicClient(baseURL: baseURL, apiToken: apiToken)
        }
        return OpenAICompatibleClient(baseURL: baseURL, apiToken: apiToken)
    }
}
