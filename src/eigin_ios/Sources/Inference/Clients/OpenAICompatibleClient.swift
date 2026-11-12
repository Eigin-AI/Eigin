import EiginSDK
import Foundation

/// App-facing adapter for SDK inference. Credentials, attachments and selection stay in the host.
struct OpenAICompatibleClient: LLMClient {
    let baseURL: String
    let apiToken: String
    let extraHeaders: [String: String]
    let session: URLSession
    let providerID: UUID?
    let isEiginRelay: Bool

    init(
        baseURL: String, apiToken: String, extraHeaders: [String: String] = [:],
        session: URLSession = .shared, providerID: UUID? = nil, isEiginRelay: Bool = false
    ) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.extraHeaders = extraHeaders
        self.session = session
        self.providerID = providerID
        self.isEiginRelay = isEiginRelay
    }

    private var sdk: EiginSDK.Experimental.Inference.OpenAICompatible {
        .init(
            configuration: .init(baseUrl: baseURL, apiToken: apiToken, extraHeaders: extraHeaders),
            session: session
        )
    }

    func fetchModels() async throws -> [String] {
        do { return try await sdk.fetchModels() }
        catch { throw InferenceSDKConversion.error(error) }
    }

    func validateAPIKey(model: String) async throws {
        do { try await sdk.validateAPIKey(model: model) }
        catch { throw InferenceSDKConversion.error(error) }
    }

    func chatCompletionStream(
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let completion = try await start(
            messages: messages,
            model: model,
            tools: nil,
            cacheKey: nil,
            reasoningEffort: nil,
            textOnly: true
        )
        return InferenceSDKStream.text(completion)
    }

    func chatCompletionEventStream(
        messages: [ChatMessage], model: String, tools: [ToolDefinition]? = nil,
        cacheKey: String? = nil
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        try await chatCompletionEventStream(
            messages: messages,
            model: model,
            tools: tools,
            cacheKey: cacheKey,
            reasoningEffort: nil
        )
    }

    func chatCompletionEventStream(
        messages: [ChatMessage], model: String, tools: [ToolDefinition]? = nil,
        cacheKey: String?, reasoningEffort: ReasoningEffort?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let completion = try await start(
            messages: messages,
            model: model,
            tools: tools,
            cacheKey: cacheKey,
            reasoningEffort: reasoningEffort,
            textOnly: false
        )
        return InferenceSDKStream.events(completion)
    }

    private func start(
        messages: [ChatMessage], model: String, tools: [ToolDefinition]?,
        cacheKey: String?, reasoningEffort: ReasoningEffort?, textOnly: Bool
    ) async throws -> EiginSDK.Experimental.Inference.Stream {
        let input = try InferenceSDKConversion.input(
            messages: messages, model: model, tools: tools, cacheKey: cacheKey,
            reasoningEffort: reasoningEffort, textOnly: textOnly,
            baseURL: baseURL, providerID: providerID,
            isRelay: isEiginRelay || ProviderPreset.isRelay(baseURL)
        )
        do { return try await sdk.stream(input) }
        catch { throw InferenceSDKConversion.error(error) }
    }
}
