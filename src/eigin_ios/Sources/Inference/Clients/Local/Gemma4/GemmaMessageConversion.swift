import Foundation

/// Converts the app's OpenAI-style ``ChatMessage`` history into the runtime's
/// ``GemmaRuntime/Message`` list.
///
/// Tool declarations are no longer injected here — LiteRT handles that via
/// ``ConversationConfig/tools``. Tool call history (assistant turns that made
/// calls + tool response turns) is passed with proper roles so the engine
/// applies Gemma's chat template correctly.
extension LocalClient {
    static func convertMessages(
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
                // If this assistant turn made tool calls, encode them in the
                // assistant message content using Gemma's FC markers so the
                // engine's chat template places them correctly, then immediately
                // follow with a tool-role message for each response.
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    var rendered = content
                    for tc in toolCalls {
                        rendered += renderGemmaToolCall(
                            name: tc.function.name,
                            jsonArgs: tc.function.arguments
                        )
                    }
                    appendMessage(&result, role: .assistant, content: rendered)
                    i += 1

                    // Consume following tool response messages.
                    while i < messages.count, messages[i].role == "tool" {
                        let toolMsg = messages[i]
                        let name = toolMsg.name
                            ?? toolCalls.first { $0.id == toolMsg.toolCallID }?.function.name
                            ?? "unknown"
                        appendMessage(
                            &result,
                            role: .tool,
                            content: renderGemmaToolResponse(
                                name: name,
                                content: toolMsg.content ?? ""
                            )
                        )
                        i += 1
                    }
                } else {
                    appendMessage(&result, role: .assistant, content: content)
                    i += 1
                }

            case "tool":
                // Orphan tool message (no preceding assistant with tool calls).
                // Wrap as a user turn so the model still sees the result.
                appendMessage(&result, role: .user, content: "[Tool result]: \(content)")
                i += 1

            default:
                appendMessage(&result, role: .user, content: content)
                i += 1
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
}
