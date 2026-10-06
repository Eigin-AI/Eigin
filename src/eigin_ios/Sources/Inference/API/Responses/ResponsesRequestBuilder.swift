import Foundation

/// Maps ``ChatMessage`` conversations onto the Responses API's `input` array,
/// per the SIWC preview limitations: system messages become `instructions`,
/// tool results become `function_call_output` items, tools become flat
/// function tools, and `store: false` / `stream: true` are always set.
enum ResponsesRequestBuilder {
    /// Builds the request body for a conversation.
    static func body(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]? = nil,
        attachmentStore: (any ChatAttachmentStoring)? = nil
    ) -> ResponsesRequestBody {
        var instructions: [String] = []
        var input: [ResponsesInputItem] = []

        for message in messages {
            switch message.role {
            case "system", "developer":
                if let content = message.content {
                    instructions.append(content)
                }

            case "assistant":
                if let content = message.content, !content.isEmpty {
                    input.append(.message(
                        role: "assistant",
                        content: [.outputText(content)]
                    ))
                }
                for toolCall in message.toolCalls ?? [] {
                    input.append(.functionCall(
                        callID: toolCall.id,
                        name: toolCall.function.name,
                        arguments: toolCall.function.arguments
                    ))
                }

            case "tool":
                // A tool result always follows the `function_call` item that
                // asked for it; the call keeps the association via `call_id`.
                if let callID = message.toolCallID {
                    input.append(.functionCallOutput(
                        callID: callID,
                        output: message.content ?? ""
                    ))
                }

            default:
                input.append(.message(role: message.role, content: contentParts(
                    of: message, attachmentStore: attachmentStore
                )))
            }
        }

        return ResponsesRequestBody(
            model: model,
            instructions: instructions.isEmpty
                ? nil
                : instructions.joined(separator: "\n\n"),
            input: input,
            tools: tools?.map(ResponsesFunctionTool.init(from:))
        )
    }

    /// Text plus image attachments as typed content parts. Attachments whose
    /// bytes can't be loaded are dropped (they were already announced as
    /// `[image omitted]`-style placeholders by the message pipeline).
    private static func contentParts(
        of message: ChatMessage,
        attachmentStore: (any ChatAttachmentStoring)?
    ) -> [ResponsesContentPart] {
        var parts: [ResponsesContentPart] = []
        if let text = message.content, !text.isEmpty {
            parts.append(.inputText(text))
        }
        if let attachments = message.attachments, let attachmentStore {
            for attachment in attachments where attachment.kind == .image {
                guard let data = attachmentStore.load(id: attachment.id) else { continue }
                let dataURL = "data:\(attachment.mimeType);base64,\(data.base64EncodedString())"
                parts.append(.inputImage(dataURL: dataURL))
            }
        }
        if parts.isEmpty, let text = message.content {
            parts.append(.inputText(text))
        }
        return parts
    }
}
