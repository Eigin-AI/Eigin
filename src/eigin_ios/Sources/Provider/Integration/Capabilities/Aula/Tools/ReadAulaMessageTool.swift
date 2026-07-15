import Foundation

/// Reads one Aula message thread in full, by the id returned from
/// `aula_messages_list`.
struct ReadAulaMessageTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "aula_message_read",
        displayName: Localized.Tools.Aula.readMessage,
        defaultPermissionLevel: .ask, category: .external
    )

    let name = "aula_message_read"
    var isSmallContext: Bool = false
    let provider: any AulaProvider

    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .external
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Read the full contents of an Aula message thread by its thread id.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "thread_id": .init(
                        type: "string",
                        description: "The thread id to read."
                    ),
                ],
                required: ["thread_id"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments),
              let threadID = args["thread_id"] as? String, !threadID.isEmpty
        else {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(errors: ["Missing 'thread_id' parameter"]),
                isError: true
            )
        }
        do {
            let thread = try await provider.readMessage(threadID: threadID)
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(result: thread.jsonObject),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
