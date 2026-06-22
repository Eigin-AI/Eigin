import Foundation

/// LLM client that routes inference through the Eigin relay.
///
/// Unlike the cloud clients there is no per-provider API key: each request is authorized with a
/// credit token drawn from a wallet and carries the relay key. Inference delegates to an
/// ``OpenAICompatibleClient`` pointed at the relay, wrapped in
/// ``CreditWalletManager/withCredits(_:)``
/// so a wallet that drops below the relay's admit floor (HTTP 402) fails over to the next one. The
/// model catalog is public, so ``fetchModels()`` needs no token.
struct RelayLLMClient: LLMClient {
    private let walletManager: any CreditWalletManager
    private let relayClient: any RelayClient
    private let baseURL: URL?
    private let eiginKey: String?
    private let session: URLSession

    init(
        walletManager: any CreditWalletManager,
        relayClient: any RelayClient,
        baseURL: URL? = RelayConfiguration.baseURL,
        eiginKey: String? = RelayConfiguration.apiKey,
        session: URLSession = .shared
    ) {
        self.walletManager = walletManager
        self.relayClient = relayClient
        self.baseURL = baseURL
        self.eiginKey = eiginKey
        self.session = session
    }

    func fetchModels() async throws -> [String] {
        try await relayClient.models()
    }

    /// No key to validate: relay access is gated by credits at request time.
    func validateAPIKey(model _: String) async throws {}

    func chatCompletionStream(
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await walletManager.withCredits { token in
            do {
                return try await client(token: token)
                    .chatCompletionStream(messages: messages, model: model)
            } catch OpenAICompatibleClientError.httpError(402, _) {
                throw RelayClientError.insufficientCredits(nil)
            }
        }
    }

    func chatCompletionEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey: String? = nil
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        try await walletManager.withCredits { token in
            do {
                return try await client(token: token)
                    .chatCompletionEventStream(
                        messages: messages,
                        model: model,
                        tools: tools,
                        cacheKey: cacheKey
                    )
            } catch OpenAICompatibleClientError.httpError(402, _) {
                // Translate the relay's payment-required response so `withCredits` fails over.
                throw RelayClientError.insufficientCredits(nil)
            }
        }
    }

    /// Builds an OpenAI-compatible client pointed at the relay's `/v1`, carrying the credit token
    /// as
    /// the bearer and the relay key as an extra header.
    private func client(token: String) throws -> OpenAICompatibleClient {
        guard let baseURL, let eiginKey, !eiginKey.isEmpty else {
            throw RelayClientError.notConfigured
        }
        return OpenAICompatibleClient(
            baseURL: baseURL.appendingPathComponent("v1").absoluteString,
            apiToken: token,
            extraHeaders: ["X-Eigin-Key": eiginKey],
            session: session
        )
    }
}
