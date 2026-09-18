import Foundation

struct PresentOptionsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "present_options",
        displayName: Localized.Tools.Present.options,
        description: Localized.Tools.Description.presentOptions,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "present_options"

    var executionMode: ToolExecutionMode {
        .interactive
    }

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

    var onPresentOptions: OptionsHandler?

    init(onPresentOptions: OptionsHandler? = nil) {
        self.onPresentOptions = onPresentOptions
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
            Present the user with a set of selectable options in the chat. \
            The user can pick an option or dismiss by selecting "something else" (this is \
            automatically provided) to type a custom response.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "question": .init(
                        type: "string",
                        description: "Optional question text displayed above the options"
                    ),
                    "options": .init(
                        type: "array",
                        description: "2-4 options to present",
                        items: .init(
                            type: "object",
                            properties: [
                                "label": .init(
                                    type: "string",
                                    description: "Short title, max ~3 words. Returned when selected."
                                ),
                                "description": .init(
                                    type: "string",
                                    description: "1-2 sentence description"
                                ),
                                "category": .init(
                                    type: "string",
                                    description: "Category of the option, used to pick a visual icon. Try to pick a different one for each option.",
                                    enum: OptionCategory.allCases.map { $0.rawValue }
                                ),
                            ],
                            required: ["label"]
                        )
                    ),
                ],
                required: ["options"]
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

        guard let optionsArray = args["options"] as? [[String: Any]],
              !optionsArray.isEmpty
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or empty 'options' array"]),
                isError: true
            )
        }

        let optionItems: [OptionItem] = optionsArray.compactMap { dict in
            guard let label = dict["label"] as? String else { return nil }
            let description = dict["description"] as? String ?? ""
            let categoryRaw = dict["category"] as? String
            let category = categoryRaw.flatMap { OptionCategory(rawValue: $0) }
            return OptionItem(label: label, description: description, category: category)
        }

        let question = args["question"] as? String
        let optionSet = OptionSet(id: id, question: question, options: optionItems)

        guard let handler = onPresentOptions else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(errors: ["The user is not able to interact with options right now"]),
                isError: true
            )
        }

        let selection = await handler(optionSet)

        switch selection {
        case .selected(let label):
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["selected": label]),
                isError: false
            )
        case .dismissed:
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["dismissed": true]),
                isError: false
            )
        }
    }
}
