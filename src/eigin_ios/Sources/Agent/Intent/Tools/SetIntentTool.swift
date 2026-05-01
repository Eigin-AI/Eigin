import Foundation

struct SetIntentTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "set_intent",
        displayName: Localized.Tools.Agent.setIntent,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "set_intent"
    var isSmallContext: Bool = false
    let intentService: any IntentService
    let spaceID: UUID?
    let chatID: UUID?
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .agent
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    init(
        intentService: any IntentService = PreviewIntentService(),
        spaceID: UUID? = nil,
        chatID: UUID? = nil
    ) {
        self.intentService = intentService
        self.spaceID = spaceID
        self.chatID = chatID
    }

    func definition() -> ToolDefinition {
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Set or reinforce a goal.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "content": .init(type: "string", description: "Goal description."),
                        "id": .init(
                            type: "string",
                            description: "Existing intent ID to reinforce."
                        ),
                    ]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: "Set a goal for yourself based on what the user needs. Intents guide how you help across conversations. Pass an id to reinforce an existing intent, or content to create a new one.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "content": .init(
                        type: "string",
                        description: "Natural language description of the intent. Required when creating a new intent."
                    ),
                    "id": .init(
                        type: "string",
                        description: "ID of an existing intent to reinforce. When provided, content is ignored."
                    ),
                ],
                required: nil
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }

        // Reinforce existing intent
        if let intentIDString = args["id"] as? String,
           let intentID = UUID(uuidString: intentIDString)
        {
            do {
                try await intentService.reinforce(id: intentID)
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(result: [
                        "id": intentID.uuidString,
                        "action": "reinforced",
                    ]),
                    isError: false
                )
            } catch {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: [error.localizedDescription]),
                    isError: true
                )
            }
        }

        // Create new intent
        guard let content = args["content"] as? String, !content.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(
                        errors: ["Either 'content' (to create) or 'id' (to reinforce) is required"]
                    ),
                isError: true
            )
        }

        do {
            let newID = try await intentService.create(
                content: content, agentID: agent.id,
                spaceID: spaceID, chatID: chatID
            )
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["id": newID.uuidString, "action": "created"]),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
