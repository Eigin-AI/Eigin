import Factory
import Foundation

/// HTTP client for OpenAI's Responses API under the ChatGPT subscription
/// flow (SIWC): `POST /responses`, bearer-access-token, `store: false`,
/// `stream: true`, SSE only.
///
/// The base URL is fixed — the provider record carries the
/// `openai-chatgpt://` sentinel, never a real URL — and the credential going
/// in is a short-lived access token, refreshed by the caller.
struct ResponsesAPIClient: LLMClient {
    static let apiBaseURL = "https://api.openai.com/v1"

    let baseURL: String = Self.apiBaseURL
    let apiToken: String
    let session: URLSession

    init(apiToken: String, session: URLSession = .shared) {
        self.apiToken = apiToken
        self.session = session
    }

    // MARK: - Models

    /// Account-specific model slugs, server-ordered, restricted to what the
    /// account can list (`visibility == "list"`). Both known response shapes
    /// decode; entries without `visibility` are treated as listed.
    func fetchModels() async throws -> [String] {
        let (data, response) = try await session.data(
            for: request(path: "/models", method: "GET")
        )
        try throwHTTPErrorIfFailed(response, data: data)

        let decoded = try JSONDecoder().decode(ResponsesModelsResponse.self, from: data)
        var seen = Set<String>()
        var ids: [String] = []
        func add(_ id: String?) {
            guard let id, seen.insert(id).inserted else { return }
            ids.append(id)
        }
        if let models = decoded.models {
            for entry in models {
                if entry.visibility == nil || entry.visibility == "list" {
                    add(entry.slug ?? entry.id)
                }
            }
        } else if let data = decoded.data {
            for entry in data {
                add(entry.id)
            }
        }
        return ids
    }

    /// Minimal non-streaming request to surface auth failures. Other HTTP
    /// errors are ignored — the subscription flow may reject the shape, not
    /// the credential (mirrors ``OpenAICompatibleClient/validateAPIKey``).
    func validateAPIKey(model: String) async throws {
        let body = ResponsesRequestBody(
            model: model,
            instructions: nil,
            input: [.message(role: "user", content: [.inputText("hi")])]
        )
        var request = try request(path: "/responses", method: "POST")
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ResponsesAPIError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ResponsesAPIError.invalidUser
        }
    }

    // MARK: - Streaming

    /// Plain-text variant: forwards the event stream and yields content only.
    func chatCompletionStream(
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let events = try await chatCompletionEventStream(
            messages: messages, model: model, tools: nil, cacheKey: nil
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        if case .contentDelta(let delta) = event {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Structured event stream over the SSE response.
    func chatCompletionEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]? = nil,
        cacheKey: String? = nil
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let store = Container.shared.chatAttachmentStore()
        let body = ResponsesRequestBuilder.body(
            messages: messages,
            model: model,
            tools: tools,
            attachmentStore: store
        )
        var request = try request(path: "/responses", method: "POST")
        request.httpBody = try JSONEncoder().encode(body)

        AppLogger.debug(
            "Responses request: \(public: model) with \(public: messages.count) messages, tools: \(public: tools?.count ?? 0)",
            category: .network
        )

        let (bytes, response) = try await session.bytes(for: request)
        // HTTP failures land before any stream exists — simplest to report.
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            let errorBody = await Self.readBodyPrefix(bytes, limit: 4000)
            AppLogger.error(
                "HTTP \(public: http.statusCode) from Responses API: \(private: errorBody.prefix(500))",
                category: .network
            )
            throw ResponsesAPIError.make(statusCode: http.statusCode, body: errorBody)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var sawCompletion = false
                    var hasToolCalls = false
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]" else { break }

                        guard let event = Self.decodeEvent(payload) else {
                            AppLogger.debug(
                                "Skipping unparseable Responses event: \(private: payload.prefix(200))",
                                category: .network
                            )
                            continue
                        }
                        if try ResponsesStreamParser.apply(
                            event,
                            to: continuation,
                            hasToolCalls: &hasToolCalls
                        ) {
                            sawCompletion = true
                            break
                        }
                    }

                    if !sawCompletion {
                        // Stream ended without `response.completed` — tell the
                        // consumer rather than finishing silently.
                        throw ResponsesAPIError.interruptedStream
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Plumbing

    private func request(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: Self.apiBaseURL + path) else {
            throw ResponsesAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func throwHTTPErrorIfFailed(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)
            throw ResponsesAPIError.make(statusCode: status, body: body)
        }
    }

    private static func decodeEvent(_ payload: String) -> ResponsesStreamEvent? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ResponsesStreamEvent.self, from: data)
    }

    private static func readBodyPrefix(
        _ bytes: URLSession.AsyncBytes,
        limit: Int
    ) async -> String {
        var collected = ""
        do {
            for try await byte in bytes {
                collected.unicodeScalars.append(UnicodeScalar(byte))
                if collected.count >= limit { break }
            }
        } catch {
            // The body is error-reporting; a partial read beats nothing.
        }
        return collected
    }
}
