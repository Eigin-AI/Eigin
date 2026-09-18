import Foundation

struct ListEmailsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "email_list",
        displayName: Localized.Tools.Email.list,
        description: Localized.Tools.Description.emailList,
        defaultPermissionLevel: .ask, category: .email
    )

    /// Supported range for `max_results`.
    static let minResults = 1
    static let maxResults = 50
    static let defaultResults = 10

    let name = "email_list"
    var isSmallContext: Bool = false
    let provider: any EmailProvider

    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .email
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "List recent emails from the connected inbox, newest first.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "max_results": .init(
                        type: "string",
                        description: "Maximum number of messages to return "
                            + "(default \(Self.defaultResults), max \(Self.maxResults))."
                    ),
                    "page_token": .init(
                        type: "string",
                        description: "Pass the `next_page_token` from a previous call to fetch the next page."
                    ),
                ],
                required: []
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id
        let args = ToolHelpers.parseArguments(toolCall.function.arguments) ?? [:]
        let maxResults = Int(args["max_results"] as? String ?? "") ?? Self.defaultResults
        let pageToken = args["page_token"] as? String

        do {
            let page = try await provider.listEmails(
                maxResults: min(max(maxResults, Self.minResults), Self.maxResults),
                pageToken: pageToken
            )
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: page.jsonObject),
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

extension EmailSummary {
    var jsonObject: [String: Any] {
        [
            "id": id,
            "thread_id": threadID,
            "from": from,
            "subject": subject,
            "snippet": snippet,
            "date": date,
        ]
    }
}

extension EmailPage {
    var jsonObject: [String: Any] {
        var object: [String: Any] = ["messages": messages.map(\.jsonObject)]
        if let nextPageToken {
            object["next_page_token"] = nextPageToken
        }
        return object
    }
}
