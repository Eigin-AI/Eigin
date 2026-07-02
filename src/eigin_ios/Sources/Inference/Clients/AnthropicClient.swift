import Factory
import Foundation

/// Native client for Anthropic's Messages API.
///
/// Translates between the app's generic types (``ChatMessage``, ``ChatStreamEvent``, etc.)
/// and Anthropic's native request/response format at the boundary.
struct AnthropicClient: LLMClient {
    let baseURL: String
    let apiToken: String
    let session: URLSession

    init(baseURL: String, apiToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.session = session
    }

    // MARK: - LLMClient

    func fetchModels() async throws -> [String] {
        let url = try buildURL(path: "/models")
        var request = URLRequest(url: url)
        applyHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let modelsResponse = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
        return modelsResponse.data.map(\.id).sorted()
    }

    func validateAPIKey(model: String) async throws {
        let url = try buildURL(path: "/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = AnthropicMessagesRequest(
            model: model,
            maxTokens: 1,
            cacheControl: .init(type: "ephemeral"),
            system: nil,
            messages: [AnthropicMessage(role: "user", content: .text("hi"))],
            tools: nil,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OpenAICompatibleClientError.httpError(http.statusCode)
        }
    }

    func chatCompletionStream(
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let eventStream = try await rawEventStream(messages: messages, model: model, tools: nil)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in eventStream {
                        if case .contentDelta(let text) = event {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func chatCompletionEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey _: String? = nil // TODO: Use instead of ephemeral cache
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        try await rawEventStream(messages: messages, model: model, tools: tools)
    }

    // MARK: - Request Building

    /// Converts the app's generic ``[ChatMessage]`` + ``[ToolDefinition]`` into
    /// an Anthropic Messages API request.
    private func buildRequestBody(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        stream: Bool
    ) -> AnthropicMessagesRequest {
        // Extract system messages into the top-level `system` parameter
        let systemText = messages
            .filter { $0.role == "system" }
            .compactMap(\.content)
            .joined(separator: "\n\n")

        let nonSystemMessages = messages.filter { $0.role != "system" }
        let anthropicMessages = convertMessages(nonSystemMessages)

        let anthropicTools = tools?.map { def in
            AnthropicToolDefinition(
                name: def.function.name,
                description: def.function.description,
                inputSchema: def.function.parameters
            )
        }

        return AnthropicMessagesRequest(
            model: model,
            maxTokens: 8192,
            cacheControl: .init(type: "ephemeral"),
            system: systemText.isEmpty ? nil : systemText,
            messages: anthropicMessages,
            tools: anthropicTools,
            stream: stream
        )
    }

    /// Converts a sequence of non-system ``ChatMessage`` values into Anthropic's message format.
    ///
    /// Key translations:
    /// - Assistant messages with `toolCalls` → content array with text + tool_use blocks
    /// - Tool messages (role == "tool") → user message with tool_result content block
    /// - Consecutive tool results are merged into a single user message (Anthropic requires
    /// alternating roles)
    /// - Plain user/assistant messages → string content
    private func convertMessages(_ messages: [ChatMessage]) -> [AnthropicMessage] {
        var result: [AnthropicMessage] = []

        for msg in messages {
            switch msg.role {
            case "assistant":
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    var blocks: [AnthropicContentBlock] = []
                    if let text = msg.content, !text.isEmpty {
                        blocks.append(.text(text))
                    }
                    for call in toolCalls {
                        let input = parseJSONObject(call.function.arguments)
                        blocks.append(.toolUse(id: call.id, name: call.function.name, input: input))
                    }
                    result.append(AnthropicMessage(role: "assistant", content: .blocks(blocks)))
                } else {
                    result.append(AnthropicMessage(
                        role: "assistant",
                        content: .text(msg.content ?? "")
                    ))
                }

            case "tool":
                let block = AnthropicContentBlock.toolResult(
                    toolUseID: msg.toolCallID ?? "",
                    content: msg.content ?? ""
                )
                // Merge consecutive tool results into a single user message
                if let last = result.last, last.role == "user",
                   case .blocks(var existingBlocks) = last.content,
                   existingBlocks.allSatisfy({ isToolResult($0) })
                {
                    existingBlocks.append(block)
                    result[result.count - 1] = AnthropicMessage(
                        role: "user",
                        content: .blocks(existingBlocks)
                    )
                } else {
                    result.append(AnthropicMessage(role: "user", content: .blocks([block])))
                }

            default: // "user" and any other role
                let content = buildUserContent(for: msg)
                result.append(AnthropicMessage(role: "user", content: content))
            }
        }

        return result
    }

    /// Builds the Anthropic content value for a user message.
    ///
    /// Returns a plain `.text` string when there are no attachments (preserving the
    /// existing wire format for text-only messages). Returns `.blocks` when images are
    /// present, placing image blocks before the text so context is clear to the model.
    private func buildUserContent(for msg: ChatMessage) -> AnthropicMessage.AnthropicContent {
        guard let attachments = msg.attachments, !attachments.isEmpty else {
            return .text(msg.content ?? "")
        }

        let store = Container.shared.chatAttachmentStore()
        var blocks: [AnthropicContentBlock] = []

        for attachment in attachments where attachment.kind == .image {
            guard let data = store.load(id: attachment.id) else { continue }
            let b64 = data.base64EncodedString()
            blocks.append(.image(mediaType: attachment.mimeType, data: b64))
        }

        if let text = msg.content, !text.isEmpty {
            blocks.append(.text(text))
        }

        // Fallback: if no image bytes were loadable, return plain text.
        guard !blocks.isEmpty else { return .text(msg.content ?? "") }
        return .blocks(blocks)
    }

    /// Parses a JSON string into a `[String: JSONValue]` dictionary for tool_use `input`.
    private func parseJSONObject(_ jsonString: String) -> [String: JSONValue] {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return obj.mapValues { convertToJSONValue($0) }
    }

    private func convertToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let s as String: .string(s)
        case let n as NSNumber where CFBooleanGetTypeID() == CFGetTypeID(n): .bool(n.boolValue)
        case let n as NSNumber: .number(n.doubleValue)
        case let a as [Any]: .array(a.map { convertToJSONValue($0) })
        case let d as [String: Any]: .object(d.mapValues { convertToJSONValue($0) })
        case is NSNull: .null
        default: .string(String(describing: value))
        }
    }

    private func isToolResult(_ block: AnthropicContentBlock) -> Bool {
        if case .toolResult = block { return true }
        return false
    }

    // MARK: - SSE Stream Parsing

    /// Core streaming implementation that parses Anthropic SSE events into ``ChatStreamEvent``
    /// values.
    ///
    /// Awaits the HTTP connection before returning, so the caller knows the request
    /// has been sent. Only SSE parsing happens inside the returned stream's `Task`.
    private func rawEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let url = try buildURL(path: "/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = buildRequestBody(messages: messages, model: model, tools: tools, stream: true)
        request.httpBody = try JSONEncoder().encode(body)

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
                    // Anthropic SSE uses typed `event:` lines followed by `data:` lines
                    var currentEventType: AnthropicStreamEventType?
                    // Track active tool_use blocks: index → (id, name, accumulated JSON)
                    var activeToolUses: [Int: (id: String, name: String, json: String)] = [:]

                    for try await line in bytes.lines {
                        if line.hasPrefix("event: ") {
                            let typeName = String(line.dropFirst(7))
                            currentEventType = AnthropicStreamEventType(rawValue: typeName)
                            continue
                        }

                        guard line.hasPrefix("data: "),
                              let eventType = currentEventType,
                              let data = String(line.dropFirst(6)).data(using: .utf8)
                        else {
                            continue
                        }

                        switch eventType {
                        case .contentBlockStart:
                            guard let parsed = try? JSONDecoder().decode(
                                AnthropicContentBlockStart.self,
                                from: data
                            )
                            else { continue }
                            if parsed.contentBlock.type == "tool_use",
                               let id = parsed.contentBlock.id,
                               let name = parsed.contentBlock.name
                            {
                                activeToolUses[parsed.index] = (id: id, name: name, json: "")
                            }

                        case .contentBlockDelta:
                            guard let parsed = try? JSONDecoder().decode(
                                AnthropicContentBlockDelta.self,
                                from: data
                            )
                            else { continue }
                            if parsed.delta.type == "text_delta", let text = parsed.delta.text {
                                continuation.yield(.contentDelta(text))
                            } else if parsed.delta.type == "input_json_delta",
                                      let partial = parsed.delta.partialJson
                            {
                                activeToolUses[parsed.index]?.json.append(partial)
                            }

                        case .contentBlockStop:
                            if let stopData = try? JSONSerialization
                                .jsonObject(with: data) as? [String: Any],
                                let index = stopData["index"] as? Int,
                                let toolUse = activeToolUses.removeValue(forKey: index)
                            {
                                let toolCall = ToolCall(
                                    id: toolUse.id,
                                    type: "function",
                                    function: .init(name: toolUse.name, arguments: toolUse.json)
                                )
                                continuation.yield(.toolCall(toolCall))
                            }

                        case .messageDelta:
                            guard let parsed = try? JSONDecoder().decode(
                                AnthropicMessageDelta.self,
                                from: data
                            )
                            else { continue }
                            if let reason = parsed.delta.stopReason {
                                switch reason {
                                case "tool_use":
                                    continuation.yield(.finished(.toolCalls))
                                default: // "end_turn", "max_tokens", etc.
                                    continuation.yield(.finished(.stop))
                                }
                            }

                        case .error:
                            if let parsed = try? JSONDecoder().decode(
                                AnthropicStreamError.self,
                                from: data
                            ) {
                                AppLogger.error(
                                    "Stream error: \(public: parsed.error.type) — \(private: parsed.error.message)",
                                    category: .network
                                )
                                throw OpenAICompatibleClientError.httpError(
                                    500,
                                    body: "\(parsed.error.type): \(parsed.error.message)"
                                )
                            }

                        case .messageStart, .messageStop, .ping:
                            break // no action needed
                        }

                        currentEventType = nil
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func buildURL(path: String) throws -> URL {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: base + path) else {
            throw OpenAICompatibleClientError.invalidURL(baseURL)
        }
        return url
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(apiToken, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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
