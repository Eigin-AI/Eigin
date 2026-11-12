import EiginSDK
import Foundation

/// Anthropic adapter. The host owns credentials and attachment storage.
struct AnthropicClient: LLMClient {
    let baseURL: String
    let apiToken: String
    let session: URLSession
    let attachmentStore: (any ChatAttachmentStoring)?

    init(
        baseURL: String,
        apiToken: String,
        session: URLSession = .shared,
        attachmentStore: (any ChatAttachmentStoring)? = nil
    ) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.session = session
        self.attachmentStore = attachmentStore
    }

    private var sdk: EiginSDK.Experimental.Inference.Anthropic {
        .init(
            configuration: .init(baseUrl: baseURL, apiToken: apiToken, extraHeaders: [:]),
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
        let completion = try await start(messages: messages, model: model, tools: nil)
        return InferenceSDKStream.text(completion, mapError: InferenceSDKConversion.error)
    }

    func chatCompletionEventStream(
        messages: [ChatMessage], model: String, tools: [ToolDefinition]? = nil,
        cacheKey: String? = nil
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let completion = try await start(messages: messages, model: model, tools: tools)
        return InferenceSDKStream.events(completion, mapError: InferenceSDKConversion.error)
    }

    private func start(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?
    ) async throws -> EiginSDK.Experimental.Inference.Stream {
        let input = try InferenceSDKConversion.input(
            messages: messages, model: model, tools: tools, cacheKey: nil,
            reasoningEffort: nil, textOnly: false, baseURL: baseURL, providerID: nil,
            isRelay: false,
            attachmentStore: attachmentStore
        )
        do { return try await sdk.stream(input) }
        catch { throw InferenceSDKConversion.error(error) }
    }
}
