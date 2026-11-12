import EiginSDK
import Foundation

/// App-facing adapter for SDK inference. Credentials, attachments and selection stay in the host.
struct EiginRelayLLMClient: LLMClient {
    private let baseURL: URL?
    private let eiginKey: String?
    private let walletManager: any CreditWalletManager
    private let session: URLSession
    private let providerID: UUID?

    init(
        walletManager: any CreditWalletManager,
        baseURL: URL? = RelayConfiguration.baseURL,
        eiginKey: String? = RelayConfiguration.apiKey,
        session: URLSession = .shared,
        providerID: UUID? = nil
    ) {
        self.walletManager = walletManager
        self.baseURL = baseURL
        self.eiginKey = eiginKey
        self.session = session
        self.providerID = providerID
    }

    private func sdk() throws -> EiginSDK.Experimental.Inference.EiginRelay {
        guard let baseURL, let eiginKey, !eiginKey.isEmpty else {
            throw RelayClientError.notConfigured
        }
        return try .init(
            configuration: .init(baseUrl: baseURL.absoluteString, relayKey: eiginKey),
            walletSource: EiginRelayWalletAdapter(manager: walletManager), session: session
        )
    }

    func fetchModels() async throws -> [String] {
        do { return try await sdk().fetchModels() }
        catch { throw Self.error(error) }
    }

    /// Relay authorization is checked when spending credits.
    func validateAPIKey(model _: String) async throws {}

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
        return InferenceSDKStream.text(completion, mapError: Self.error)
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
        return InferenceSDKStream.events(completion, mapError: Self.error)
    }

    private func start(
        messages: [ChatMessage], model: String, tools: [ToolDefinition]?,
        cacheKey: String?, reasoningEffort: ReasoningEffort?, textOnly: Bool
    ) async throws -> EiginSDK.Experimental.Inference.Stream {
        let input = try InferenceSDKConversion.input(
            messages: messages, model: model, tools: tools, cacheKey: cacheKey,
            reasoningEffort: reasoningEffort, textOnly: textOnly,
            baseURL: baseURL?.appendingPathComponent("v1").absoluteString ?? "",
            providerID: providerID, isRelay: true
        )
        do { return try await sdk().stream(input) }
        catch { throw Self.error(error) }
    }

    private static func error(_ error: any Error) -> any Error {
        switch error {
        case EiginSDK.Experimental.Inference.Failure.NoCredits:
            CreditsError.noCreditsRemaining
        case EiginSDK.Experimental.Inference.Failure.EiginRelayNotConfigured:
            RelayClientError.notConfigured
        default:
            InferenceSDKConversion.error(error)
        }
    }
}
