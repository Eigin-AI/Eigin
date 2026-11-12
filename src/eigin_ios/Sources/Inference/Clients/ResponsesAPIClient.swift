import EiginSDK
import Foundation

/// ChatGPT subscription adapter. The host supplies a refreshed access token.
struct ResponsesAPIClient: LLMClient {
    static let apiBaseURL = "https://api.openai.com/v1"

    let baseURL: String = Self.apiBaseURL
    let apiToken: String
    let session: URLSession
    let attachmentStore: (any ChatAttachmentStoring)?

    init(
        apiToken: String,
        session: URLSession = .shared,
        attachmentStore: (any ChatAttachmentStoring)? = nil
    ) {
        self.apiToken = apiToken
        self.session = session
        self.attachmentStore = attachmentStore
    }

    private var sdk: EiginSDK.Experimental.Inference.OpenAIResponses {
        .init(
            configuration: .init(baseUrl: baseURL, apiToken: apiToken, extraHeaders: [:]),
            session: session
        )
    }

    func fetchModels() async throws -> [String] {
        do { return try await sdk.fetchModels() }
        catch { throw ResponsesSDKConversion.error(error) }
    }

    func validateAPIKey(model: String) async throws {
        do { try await sdk.validateAPIKey(model: model) }
        catch { throw ResponsesSDKConversion.error(error) }
    }

    func chatCompletionStream(
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let completion = try await start(messages: messages, model: model, tools: nil)
        return InferenceSDKStream.text(completion, mapError: ResponsesSDKConversion.error)
    }

    func chatCompletionEventStream(
        messages: [ChatMessage], model: String, tools: [ToolDefinition]? = nil,
        cacheKey: String? = nil
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let completion = try await start(messages: messages, model: model, tools: tools)
        return InferenceSDKStream.events(completion, mapError: ResponsesSDKConversion.error)
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
        catch { throw ResponsesSDKConversion.error(error) }
    }
}
