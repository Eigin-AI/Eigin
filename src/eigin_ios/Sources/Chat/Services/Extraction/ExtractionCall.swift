import Foundation

/// A single few-shot example for an extraction prompt.
struct FewShotExample {
    let userMessage: String
    let assistantResponse: String
}

/// Result of an extraction attempt.
enum ExtractionResult: Equatable {
    /// The tag was found. `reason` is the model's chain-of-thought (nil if not provided).
    case extracted(value: String, reason: String?)
    /// The model produced output but the expected tag was not present.
    case noMatch(rawOutput: String)
    /// The model produced no output.
    case empty
}

/// Runs a stateless few-shot extraction call against an LLM.
///
/// Builds the system prompt internally from the tag name and a plain-language
/// description of what to extract. The extraction format is always
/// `<tag reason="...">value</tag>`. The `reason` attribute acts as
/// chain-of-thought to help small models warm up to the task — it is not
/// the primary output.
///
/// This is a side-channel call — it is not shown to the user.
struct ExtractionCall {
    let chatService: ChatService

    /// Runs extraction against the given user input.
    ///
    /// - Parameters:
    ///   - tag: XML element name to extract (e.g. `"name"`).
    ///   - description: Plain-language description of what to extract (e.g. `"the user's name"`).
    ///   - examples: Few-shot user/assistant pairs demonstrating the extraction format.
    ///   - input: The real user message to extract from.
    ///   - baseURL: Provider base URL.
    ///   - providerID: Provider UUID for keychain key resolution.
    ///   - model: Model identifier string.
    /// - Returns: The extraction result.
    func run(
        tag: String,
        description: String,
        examples: [FewShotExample],
        input: String,
        context: String? = nil,
        baseURL: String,
        providerID: UUID,
        model: String
    ) async throws -> ExtractionResult {
        let systemPrompt = buildSystemPrompt(tag: tag, description: description)
        let formattedInput = formatInput(input, context: context)
        let messages = buildMessages(
            systemPrompt: systemPrompt,
            examples: examples,
            input: formattedInput
        )

        let stream = try await chatService.chatCompletionStream(
            baseURL: baseURL,
            providerID: providerID,
            messages: messages,
            model: model
        )

        var output = ""
        for try await token in stream {
            output += token
        }

        return XMLTagParser.extract(tag: tag, from: output)
    }

    // MARK: - Private

    private func buildSystemPrompt(tag: String, description: String) -> String {
        """
        Given the user input, extract \(description) in the format \
        <\(tag) reason="...">\(tag) value</\(tag)>.
        Only do this if \(description) is clearly provided in the input.
        The user may respond in any language.
        If not provided, respond with NONE.
        """
    }

    private func buildMessages(
        systemPrompt: String,
        examples: [FewShotExample],
        input: String
    ) -> [ChatMessage] {
        var messages: [ChatMessage] = [
            ChatMessage(role: "system", content: systemPrompt),
        ]
        for example in examples {
            messages.append(ChatMessage(role: "user", content: example.userMessage))
            messages.append(ChatMessage(role: "assistant", content: example.assistantResponse))
        }
        messages.append(ChatMessage(role: "user", content: input))
        return messages
    }

    private func formatInput(_ input: String, context: String?) -> String {
        guard let context, !context.isEmpty else { return input }
        return "[Assistant: \"\(context)\"] \"\(input)\""
    }
}
