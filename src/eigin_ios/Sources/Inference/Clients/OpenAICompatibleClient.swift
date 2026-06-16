import Foundation

/// HTTP client for any provider that implements the OpenAI-compatible REST API (`/models`,
/// `/chat/completions`).
/// The base URL should already include the version prefix (e.g. `https://api.openai.com/v1`).
struct OpenAICompatibleClient: LLMClient {
    let baseURL: String
    let apiToken: String
    /// Extra headers applied to every request (e.g. the relay's `X-Eigin-Key`).
    let extraHeaders: [String: String]
    let session: URLSession

    init(
        baseURL: String,
        apiToken: String,
        extraHeaders: [String: String] = [:],
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.extraHeaders = extraHeaders
        self.session = session
    }

    /// Applies the configured extra headers to a request.
    private func applyExtraHeaders(to request: inout URLRequest) {
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    /// Resolves the provider adapter for a specific model, using both the base URL
    /// and model name so routed models (e.g. Mistral on OpenRouter) get the right adapter.
    private func adapter(for model: String) -> ProviderAdapter {
        ProviderAdapterFactory.adapter(for: baseURL, model: model)
    }

    /// Fetches the list of available model IDs from the provider, returned sorted alphabetically.
    func fetchModels() async throws -> [String] {
        let url = try buildURL(path: "/models")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        applyExtraHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return modelsResponse.data.map(\.id).sorted()
    }

    /// Validates the API key by making a minimal non-streaming completion request.
    /// Only throws on authentication failures (401/403). Other HTTP errors (404, 400, etc.)
    /// are ignored because they likely mean the chosen model doesn't support chat completions,
    /// not that the key is invalid — especially for providers like Google whose `/models`
    /// endpoint already requires auth.
    func validateAPIKey(model: String) async throws {
        let url = try buildURL(path: "/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyExtraHeaders(to: &request)

        var body = ChatCompletionRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: "hi")],
            stream: false
        )
        body.maxTokens = 1
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        // Only treat auth failures as validation errors
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OpenAICompatibleClientError.httpError(http.statusCode)
        }
    }

    /// Opens a streaming chat completion request and yields content deltas as they arrive via
    /// server-sent events.
    func chatCompletionStream(
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let url = try buildURL(path: "/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyExtraHeaders(to: &request)

        let body = ChatCompletionRequest(
            model: model,
            messages: messages,
            stream: true
        )
        let encoded = try JSONEncoder().encode(body)
        request.httpBody = try adapter(for: model).processRequestBody(encoded, messages: messages)

        let (bytes, response) = try await session.bytes(for: request)
        try validateResponse(response)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" { break }

                        guard let chunkData = payload.data(using: .utf8) else { continue }

                        // Check for inline error before normal decoding
                        if let streamError = try? JSONDecoder().decode(
                            StreamErrorResponse.self,
                            from: chunkData
                        ) {
                            throw OpenAICompatibleClientError.httpError(
                                0,
                                body: streamError.error.message
                            )
                        }

                        let chunk = try JSONDecoder().decode(
                            ChatCompletionChunk.self,
                            from: chunkData
                        )

                        if let content = chunk.choices.first?.delta.content {
                            continuation.yield(content)
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

    /// Opens a streaming chat completion request and yields structured events
    /// including content deltas and tool calls.
    func chatCompletionEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]? = nil
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let url = try buildURL(path: "/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyExtraHeaders(to: &request)

        var body = ChatCompletionRequest(
            model: model,
            messages: messages,
            stream: true
        )
        body.tools = tools
        let encoded = try JSONEncoder().encode(body)
        let resolvedAdapter = adapter(for: model)
        request.httpBody = try resolvedAdapter.processRequestBody(encoded, messages: messages)

        AppLogger.debug(
            "Request: \(public: model) with \(public: messages.count) messages, tools: \(public: tools?.count ?? 0)",
            category: .network
        )
        let (bytes, response) = try await session.bytes(for: request)

        // Handle HTTP errors before returning the stream
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            AppLogger.error(
                "HTTP \(public: http.statusCode) error: \(private: errorBody.prefix(500))",
                category: .network
            )
            throw OpenAICompatibleClientError.httpError(
                http.statusCode,
                body: errorBody.isEmpty ? nil : String(errorBody.prefix(2000))
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var accumulator = ToolCallAccumulator()
                    var didFinish = false
                    var lineCount = 0

                    for try await line in bytes.lines {
                        lineCount += 1
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" {
                            AppLogger.debug(
                                "[DONE] at line \(public: lineCount)",
                                category: .network
                            )
                            break
                        }

                        guard let chunkData = payload.data(using: .utf8) else { continue }

                        let chunk: ChatCompletionChunk
                        do {
                            chunk = try JSONDecoder().decode(
                                ChatCompletionChunk.self,
                                from: chunkData
                            )
                        } catch {
                            // Check for an inline error object before skipping
                            if let streamError = try? JSONDecoder().decode(
                                StreamErrorResponse.self,
                                from: chunkData
                            ) {
                                AppLogger.error(
                                    "Inline error: \(public: streamError.error.type) — \(private: streamError.error.message)",
                                    category: .network
                                )
                                throw OpenAICompatibleClientError.httpError(
                                    0,
                                    body: streamError.error.message
                                )
                            }
                            AppLogger.debug(
                                "Skipping unparseable chunk: \(private: error.localizedDescription) — raw: \(private: payload.prefix(200))",
                                category: .network
                            )
                            continue
                        }

                        guard let choice = chunk.choices.first else { continue }

                        // Accumulate content deltas
                        if let content = choice.delta.content {
                            continuation.yield(.contentDelta(content))
                        }

                        // Accumulate tool call deltas
                        if let toolCallDeltas = choice.delta.toolCalls {
                            for delta in toolCallDeltas {
                                accumulator.feed(delta)
                            }
                        }

                        // Check finish reason — break out immediately to avoid
                        // writing to the continuation after it's consumed.
                        if let reason = choice.finishReason {
                            if reason == "tool_calls" ||
                                (resolvedAdapter.treatsStopAsToolCalls && accumulator.hasToolCalls)
                            {
                                // Emit provider metadata before tool calls so the
                                // consumer can attach it to the assistant message.
                                if let meta = accumulator.capturedProviderMetadata {
                                    continuation.yield(.providerMetadata(meta))
                                }
                                let calls = accumulator.finalize()
                                if !calls.isEmpty {
                                    for call in calls {
                                        continuation.yield(.toolCall(call))
                                    }
                                    continuation.yield(.finished(.toolCalls))
                                } else {
                                    continuation.yield(.finished(.stop))
                                }
                            } else {
                                continuation.yield(.finished(.stop))
                            }
                            didFinish = true
                            break
                        }
                    }

                    AppLogger.debug(
                        "Stream done. \(public: lineCount) lines, didFinish=\(public: didFinish)",
                        category: .network
                    )

                    // Fallback: if the stream ended without an explicit finish_reason
                    // (e.g. the chunk was skipped), emit .finished(.stop) so the
                    // consumer doesn't hang.
                    if !didFinish {
                        // Check if we accumulated tool calls without a finish_reason
                        if let meta = accumulator.capturedProviderMetadata {
                            continuation.yield(.providerMetadata(meta))
                        }
                        let leftover = accumulator.finalize()
                        if !leftover.isEmpty {
                            for call in leftover {
                                continuation.yield(.toolCall(call))
                            }
                            continuation.yield(.finished(.toolCalls))
                        } else {
                            continuation.yield(.finished(.stop))
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

    private func buildURL(path: String) throws -> URL {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: base + path) else {
            throw OpenAICompatibleClientError.invalidURL(baseURL)
        }
        return url
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OpenAICompatibleClientError.httpError(http.statusCode)
        }
    }
}
