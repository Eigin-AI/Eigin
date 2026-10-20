import Foundation

struct ManageVocabularyTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "manage_vocabulary",
        displayName: Localized.Tools.Manage.vocabulary,
        description: Localized.Tools.Description.manageVocabulary,
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
            Manage the agent's custom vocabulary, used to correct likely speech \
            misrecognitions: dictated words close to a vocabulary word surface as \
            hints on the turn.
            When you notice a spoken word was misrecognized (e.g. "eigen" for \
            "Eigin"), add the intended word AND record the misheard word as its \
            alias (action 'add_alias') so future turns hint the correction. \
            Keep words current — remove ones that no longer matter.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "action": .init(
                        type: "string",
                        description: "'add' adds words, 'add_alias' records known mishearings, 'remove' removes words, 'list' shows everything.",
                        enum: ["add", "add_alias", "remove", "list"]
                    ),
                    "words": .init(
                        type: "array",
                        description:
                        "Words to add or remove. Required for add/remove, ignored for others.",
                        items: .init(type: "string")
                    ),
                    "word": .init(
                        type: "string",
                        description:
                        "The vocabulary word the variations belong to. Required for add_alias."
                    ),
                    "variations": .init(
                        type: "array",
                        description:
                        "Words the transcriber is known to produce instead of 'word' (e.g. [\"eigen\", \"iGen\"] for \"Eigin\"). Required for add_alias.",
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
                    "status": "OK", "added": words,
                    "all_user_words": store.userEntries().map(\.word),
                ]),
                isError: false
            )

        case "add_alias":
            guard let word = args["word"] as? String, !word.isEmpty else {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: ["Missing 'word' parameter"]),
                    isError: true
                )
            }
            guard let variations = args["variations"] as? [String], !variations.isEmpty else {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: ["Missing or empty 'variations' array"]),
                    isError: true
                )
            }
            for variation in variations {
                store.addAlias(variation, for: word)
            }
            refreshDictation(store: store, agentName: agent.name)
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "status": "OK", "word": word, "variations": variations,
                    "all_user_words": store.userEntries().map(\.word),
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
                    "status": "OK", "removed": words,
                    "all_user_words": store.userEntries().map(\.word),
                ]),
                isError: false
            )

        case "list":
            let userEntries = store.userEntries()
            let allEntries = store.entries(agentName: agent.name)
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "user_words": userEntries.map(\.word),
                    "user_aliases": Dictionary(
                        uniqueKeysWithValues: userEntries.map { ($0.word, $0.aliases) }
                    ).filter { !$0.value.isEmpty },
                    "all_words": allEntries.map(\.word),
                ]),
                isError: false
            )

        default:
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [
                    "Invalid action '\(action)'. Must be 'add', 'add_alias', 'remove', or 'list'.",
                ]), isError: true
            )
        }
    }

    private func refreshDictation(store: any VocabularyStore, agentName: String) {
        dictationService?.setContextualStrings(store.allWords(agentName: agentName))
    }
}
