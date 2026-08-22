import Foundation

struct ReplyEmailTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "email_reply",
        displayName: Localized.Tools.Email.reply,
        defaultPermissionLevel: .ask, category: .external
    )

    let name = "email_reply"
    var isSmallContext: Bool = false
    let provider: any EmailProvider

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
            description: "Reply to an email and send it immediately, in the same thread.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "message_id": .init(
                        type: "string",
                        description: "The id of the message being replied to."
                    ),
                    "body": .init(type: "string", description: "Reply body text."),
                ],
                required: ["message_id", "body"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        let body = ToolHelpers.stringArgument(toolCall, "body")
        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.replyToEmail,
            detail: body.map { .block($0) }
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let args = ToolHelpers.parseArguments(toolCall.function.arguments) ?? [:]

        var missing: [String] = []
        let messageID = args["message_id"] as? String
        if messageID == nil || messageID!.isEmpty { missing.append("message_id") }
        let body = args["body"] as? String
        if body == nil { missing.append("body") }
        guard missing.isEmpty, let messageID, let body else {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(
                    errors: ["Missing required parameter(s): \(missing.joined(separator: ", "))"]
                ),
                isError: true
            )
        }

        do {
            let sent = try await provider.replyEmail(messageID: messageID, body: body)
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(result: sent.jsonObject.merging(
                    ["status": "sent"]
                ) { current, _ in current }),
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
