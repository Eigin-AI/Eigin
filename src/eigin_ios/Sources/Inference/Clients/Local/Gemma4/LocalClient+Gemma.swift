import Foundation

extension LocalClient {
    static func gemmaStatus() async -> LocalModelStatus {
        let state = await GemmaModelManager.shared.state
        switch state {
        case .notDownloaded:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .notDownloaded
            )
        case .downloading(let progress):
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .downloading(progress: progress)
            )
        case .downloaded, .compiling:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .downloading(progress: 1.0)
            )
        case .ready:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .ready
            )
        case .failed(let message):
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .unavailable(reason: message)
            )
        }
    }

    static func allLocalModelStatuses() async -> [LocalModelStatus] {
        var statuses = [LocalModelStatus]()
        await statuses.append(appleFoundationModelStatus())
        await statuses.append(gemmaStatus())
        return statuses
    }

    func gemmaEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let manager = await GemmaModelManager.shared

        // Gate before any load. Devices below the RAM bar OOM-crash on load — a
        // jetsam kill that can't be caught — so we must refuse up front and let
        // this surface as a chat error.
        guard await manager.hasRequiredRAM() else {
            throw await LocalClientError.deviceUnsupported(
                detail: manager.insufficientResourcesDetail()
            )
        }

        if await manager.llm == nil {
            try await manager.load()
        }
        guard let llm = await manager.llm else {
            throw LocalClientError.modelNotLoaded
        }

        let libraryMessages = Self.convertMessages(messages, tools: tools)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    llm.reset()

                    let maxTokens = KnownModelCatalog.lookup("gemma-4-e2b")?.maxOutput ?? 256

                    let generationStart = ContinuousClock.now
                    var firstTokenTime: ContinuousClock.Instant?
                    var tokenCount = 0

                    var filter = GemmaStreamFilter()

                    for await token in try await llm.stream(
                        libraryMessages,
                        maxTokens: maxTokens
                    ) {
                        if firstTokenTime == nil {
                            firstTokenTime = .now
                        }
                        tokenCount += 1

                        let emission = filter.feed(token)
                        if !emission.isEmpty {
                            continuation.yield(.contentDelta(emission))
                        }
                    }

                    let tail = filter.flush()
                    if !tail.isEmpty {
                        continuation.yield(.contentDelta(tail))
                    }

                    let toolCalls = Self.parseToolCalls(filter.fullOutput)
                    if !toolCalls.isEmpty {
                        for call in toolCalls {
                            continuation.yield(.toolCall(call))
                        }
                        continuation.yield(.finished(.toolCalls))
                    } else {
                        continuation.yield(.finished(.stop))
                    }

                    let totalMs = generationStart.duration(to: .now).ms
                    let decodeMs = firstTokenTime.map { $0.duration(to: .now).ms } ?? totalMs
                    let tokPerSec = decodeMs > 0
                        ? String(format: "%.1f", Double(tokenCount) / (Double(decodeMs) / 1000))
                        : "–"

                    AppLogger.info(
                        "Gemma: \(public: tokenCount) tokens, \(public: decodeMs)ms (\(public: tokPerSec) tok/s)",
                        category: .chat
                    )

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Message Conversion

    private static func convertMessages(
        _ messages: [ChatMessage],
        tools: [ToolDefinition]?
    ) -> [GemmaRuntime.Message] {
        var result: [GemmaRuntime.Message] = []
        var i = 0
        while i < messages.count {
            let message = messages[i]
            let content = message.content ?? ""

            switch message.role {
            case "system":
                appendMessage(&result, role: .system, content: content)
                i += 1
            case "user":
                appendMessage(&result, role: .user, content: content)
                i += 1
            case "assistant":
                var rendered = content
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    for tc in toolCalls {
                        let callText = renderGemmaToolCall(
                            name: tc.function.name,
                            jsonArgs: tc.function.arguments
                        )
                        rendered += callText
                    }
                    var j = i + 1
                    while j < messages.count, messages[j].role == "tool" {
                        let toolMsg = messages[j]
                        let matchedCall = toolCalls.first {
                            $0.id == toolMsg.toolCallID
                        }
                        let name = toolMsg.name ?? matchedCall?.function.name ?? "unknown"
                        let responseText = renderGemmaToolResponse(
                            name: name,
                            content: toolMsg.content ?? ""
                        )
                        rendered += responseText
                        j += 1
                    }
                    appendMessage(&result, role: .assistant, content: rendered)
                    i = j
                } else {
                    appendMessage(&result, role: .assistant, content: rendered)
                    i += 1
                }
            case "tool":
                let fallback = "[Tool result]: \(content)"
                appendMessage(&result, role: .user, content: fallback)
                i += 1
            default:
                appendMessage(&result, role: .user, content: content)
                i += 1
            }
        }

        if let tools, !tools.isEmpty {
            let toolBlock = renderGemmaToolDeclarations(tools)
            if let firstSystemIdx = result.firstIndex(where: { $0.role == .system }) {
                let existing = result[firstSystemIdx].content
                result[firstSystemIdx] = GemmaRuntime.Message(
                    role: .system,
                    content: existing + toolBlock
                )
            } else {
                result.insert(
                    GemmaRuntime.Message(role: .system, content: toolBlock),
                    at: 0
                )
            }
        }

        return result
    }

    private static func appendMessage(
        _ messages: inout [GemmaRuntime.Message],
        role: GemmaRuntime.Message.Role,
        content: String
    ) {
        guard !content.isEmpty else { return }
        if messages.last?.role == role {
            let existing = messages[messages.count - 1].content
            messages[messages.count - 1] = GemmaRuntime.Message(
                role: role,
                content: existing + "\n" + content
            )
        } else {
            messages.append(GemmaRuntime.Message(role: role, content: content))
        }
    }

    // MARK: - Gemma Native Rendering

    private static func renderGemmaToolDeclarations(_ tools: [ToolDefinition]) -> String {
        tools.map { tool in
            var body = "declaration:\(tool.function.name){"
            body += "description:<|\"|>\(escapeGemmaString(tool.function.description))<|\"|>"

            let schema = tool.function.parameters
            body += ",parameters:{"

            if let properties = schema.properties, !properties.isEmpty {
                let propEntries = properties.map { key, prop in
                    renderGemmaProperty(key: key, property: prop)
                }
                body += "properties:{" + propEntries.joined(separator: ",") + "}"
            }

            if let required = schema.required, !required.isEmpty {
                if !(schema.properties?.isEmpty ?? true) { body += "," }
                let reqList = required.map { "<|\"|>\($0)<|\"|>" }.joined(separator: ",")
                body += "required:[\(reqList)]"
            }

            body += ",type:<|\"|>\(schema.type.uppercased())<|\"|>"
            body += "}"
            body += "}"

            return "<|tool>\(body)<tool|>"
        }.joined(separator: "")
    }

    private static func renderGemmaProperty(
        key: String,
        property: JSONSchema.Property
    ) -> String {
        var parts: [String] = []
        if !property.description.isEmpty {
            parts.append("description:<|\"|>\(escapeGemmaString(property.description))<|\"|>")
        }
        if let enumValues = property.enum, !enumValues.isEmpty {
            let list = enumValues.map { "<|\"|>\(escapeGemmaString($0))<|\"|>" }
                .joined(separator: ",")
            parts.append("enum:[\(list)]")
        }
        parts.append("type:<|\"|>\(property.type.uppercased())<|\"|>")
        return "\(key):{\(parts.joined(separator: ","))}"
    }

    private static func renderGemmaToolCall(name: String, jsonArgs: String) -> String {
        let gemmaArgs = convertJSONArgsToGemma(jsonArgs)
        return "<|tool_call>call:\(name)\(gemmaArgs)<tool_call|>"
    }

    private static func renderGemmaToolResponse(name: String, content: String) -> String {
        let body: String
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            body = convertJSONArgsToGemma(trimmed)
        } else {
            body = "{value:<|\"|>\(escapeGemmaString(content))<|\"|>}"
        }
        return "<|tool_response>response:\(name)\(body)<tool_response|>"
    }

    private static func escapeGemmaString(_ s: String) -> String {
        s.replacingOccurrences(of: "<|\"|>", with: "\"")
    }

    // MARK: - Tool Call Parsing

    static func parseToolCalls(_ output: String) -> [ToolCall] {
        var calls: [ToolCall] = []

        let pattern = #"<\|tool_call>call:([A-Za-z_][A-Za-z0-9_]*)(\{.*?\})<tool_call\|>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else { return [] }

        let nsOutput = output as NSString
        let matches = regex.matches(
            in: output,
            range: NSRange(location: 0, length: nsOutput.length)
        )
        for match in matches where match.numberOfRanges >= 3 {
            let name = nsOutput.substring(with: match.range(at: 1))
            let gemmaArgs = nsOutput.substring(with: match.range(at: 2))
            let jsonArgs = convertGemmaArgsToJSON(gemmaArgs)
            calls.append(ToolCall(
                id: UUID().uuidString,
                type: "function",
                function: ToolCall.FunctionCall(name: name, arguments: jsonArgs)
            ))
        }
        return calls
    }

    static func convertGemmaArgsToJSON(_ gemmaArgs: String) -> String {
        var converted = gemmaArgs.replacingOccurrences(of: "<|\"|>", with: "\"")
        let keyPattern = #"([\{,\s])([A-Za-z_][A-Za-z0-9_]*)\s*:"#
        if let regex = try? NSRegularExpression(pattern: keyPattern, options: []) {
            let mutable = NSMutableString(string: converted)
            regex.replaceMatches(
                in: mutable,
                options: [],
                range: NSRange(location: 0, length: mutable.length),
                withTemplate: "$1\"$2\":"
            )
            converted = mutable as String
        }
        return converted
    }

    static func convertJSONArgsToGemma(_ jsonArgs: String) -> String {
        guard let data = jsonArgs.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return jsonArgs
        }
        return renderGemmaValue(obj)
    }

    private static func renderGemmaValue(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            let entries = dict.map { key, val in
                "\(key):\(renderGemmaValue(val))"
            }
            return "{" + entries.joined(separator: ",") + "}"
        }
        if let arr = value as? [Any] {
            return "[" + arr.map { renderGemmaValue($0) }.joined(separator: ",") + "]"
        }
        if let str = value as? String {
            return "<|\"|>\(escapeGemmaString(str))<|\"|>"
        }
        if let b = value as? Bool {
            return b ? "true" : "false"
        }
        if let n = value as? NSNumber {
            return n.stringValue
        }
        return "null"
    }
}

// MARK: - Stream Filter

private struct GemmaStreamFilter {
    private(set) var fullOutput = ""
    private var emittedCount = 0

    mutating func feed(_ token: String) -> String {
        fullOutput += token
        return drain(allowTrailingPartialMarker: true)
    }

    mutating func flush() -> String {
        drain(allowTrailingPartialMarker: false)
    }

    private mutating func drain(allowTrailingPartialMarker: Bool) -> String {
        let cleaned = cleanedSoFar()

        let trailingReserve = allowTrailingPartialMarker ? Self
            .openMarkerPrefixLength(in: cleaned) : 0
        let emittableEnd = cleaned.count - trailingReserve
        guard emittableEnd > emittedCount else { return "" }

        let startIdx = cleaned.index(cleaned.startIndex, offsetBy: emittedCount)
        let endIdx = cleaned.index(cleaned.startIndex, offsetBy: emittableEnd)
        let chunk = String(cleaned[startIdx ..< endIdx])
        emittedCount = emittableEnd
        return chunk
    }

    private func cleanedSoFar() -> String {
        var out = fullOutput
        let patterns = [
            #"<\|tool_call>.*?<tool_call\|>"#,
            #"<\|tool_response>.*?<tool_response\|>"#,
            #"<\|tool_response>"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators]
            ) {
                let mutable = NSMutableString(string: out)
                regex.replaceMatches(
                    in: mutable,
                    options: [],
                    range: NSRange(location: 0, length: mutable.length),
                    withTemplate: ""
                )
                out = mutable as String
            }
        }
        return out
    }

    private static func openMarkerPrefixLength(in text: String) -> Int {
        let markers = ["<|tool_call>", "<|tool_response>"]
        var best = 0
        for marker in markers {
            let maxPrefix = min(marker.count - 1, text.count)
            for n in stride(from: maxPrefix, through: 1, by: -1) {
                let prefix = String(marker.prefix(n))
                if text.hasSuffix(prefix) {
                    best = max(best, n)
                    break
                }
            }
        }
        return best
    }
}

private extension Duration {
    var ms: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
