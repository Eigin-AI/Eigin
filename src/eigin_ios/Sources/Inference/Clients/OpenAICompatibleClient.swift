import EiginSDK
import Factory
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
        catch { throw OpenAICompatibleSDKConversion.error(error) }
    }

    func validateAPIKey(model: String) async throws {
        do { try await sdk.validateAPIKey(model: model) }
        catch { throw OpenAICompatibleSDKConversion.error(error) }
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
        return AsyncThrowingStream(unfolding: {
            do {
                while let event = try await completion.next() {
                    if case .contentDelta(let text) = event { return text }
                }
                return nil
            } catch { throw OpenAICompatibleSDKConversion.error(error) }
        })
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
        return AsyncThrowingStream(unfolding: {
            do { return try await completion.next().map(OpenAICompatibleSDKConversion.event) }
            catch { throw OpenAICompatibleSDKConversion.error(error) }
        })
    }

    private func start(
        messages: [ChatMessage], model: String, tools: [ToolDefinition]?,
        cacheKey: String?, reasoningEffort: ReasoningEffort?, textOnly: Bool
    ) async throws -> EiginSDK.Experimental.Inference.Stream {
        let store = Container.shared.chatAttachmentStore()
        let origin = ReasoningOrigin.destination(
            providerID: providerID,
            baseURL: baseURL,
            model: model
        )
        let input = try EiginSDK.Experimental.Inference.Input(
            model: model, messages: messages.map { OpenAICompatibleSDKConversion.message(
                $0,
                store: store
            ) },
            tools: tools?.map(OpenAICompatibleSDKConversion.tool),
            reasoningEffort: reasoningEffort?.rawValue,
            promptCacheKey: cacheKey,
            modelFamily: OpenAICompatibleSDKConversion
                .family(KnownModelCatalog.lookup(model)?.family),
            isRelay: isEiginRelay || ProviderPreset.isRelay(baseURL),
            reasoningOrigin: origin.map(OpenAICompatibleSDKConversion.origin), textOnly: textOnly
        )
        do { return try await sdk.stream(input) }
        catch { throw OpenAICompatibleSDKConversion.error(error) }
    }
}
