import Foundation

struct ManageVocabularyTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "manage_vocabulary",
        displayName: Localized.Tools.Manage.vocabulary,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "manage_vocabulary"
    var isSmallContext: Bool = false
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

    nonisolated(unsafe) var vocabularyStore: (any VocabularyStore)?
    nonisolated(unsafe) var dictationService: (any DictationService)?

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
            Manage the speech recognition vocabulary. Adding words here improves
            dictation accuracy for names, jargon, and specialized terms.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "action": .init(
                        type: "string",
                        description: "Use 'list' to see current words, 'add' to add new words, 'remove' to remove words.",
                        enum: ["add", "remove", "list"]
                    ),
                    "words": .init(
                        type: "array",
                        description:
                        "Words to add or remove. Required for add/remove, ignored for list.",
                        items: .init(type: "string")
                    ),
                ],
                required: ["action"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }
        guard let action = args["action"] as? String else {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: ["Missing 'action' parameter"]),
                isError: true
            )
        }
        guard let store = vocabularyStore else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Vocabulary store not available"]),
                isError: true
            )
        }

        switch action {
        case "add":
            guard let words = args["words"] as? [String], !words.isEmpty else {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: ["Missing or empty 'words' array"]),
                    isError: true
                )
            }
            store.addWords(words)
            refreshDictation(store: store, agentName: agent.name)
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "status": "OK", "added": words, "all_user_words": store.userWords(),
                ]),
                isError: false
            )

        case "remove":
            guard let words = args["words"] as? [String], !words.isEmpty else {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: ["Missing or empty 'words' array"]),
                    isError: true
                )
            }
            store.removeWords(words)
            refreshDictation(store: store, agentName: agent.name)
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "status": "OK", "removed": words, "all_user_words": store.userWords(),
                ]),
                isError: false
            )

        case "list":
            let userWords = store.userWords()
            let allWords = store.allWords(agentName: agent.name)
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "user_words": userWords, "all_words": allWords,
                ]),
                isError: false
            )

        default:
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [
                    "Invalid action '\(action)'. Must be 'add', 'remove', or 'list'.",
                ]), isError: true
            )
        }
    }

    private func refreshDictation(store: any VocabularyStore, agentName: String) {
        dictationService?.setContextualStrings(store.allWords(agentName: agentName))
    }
}
