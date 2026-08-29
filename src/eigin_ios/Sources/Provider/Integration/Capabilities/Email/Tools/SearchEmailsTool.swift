import Foundation

struct SearchEmailsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "email_search",
        displayName: Localized.Tools.Email.search,
        defaultPermissionLevel: .ask, category: .email
    )

    /// Supported range for `max_results`.
    static let minResults = 1
    static let maxResults = 50
    static let defaultResults = 10

    let name = "email_search"
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
            description: "Search emails in the connected inbox by sender, subject, or content.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "query": .init(
                        type: "string",
                        description: "Search query (e.g. 'from:alice subject:invoice')."
                    ),
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
                required: ["query"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let query = ToolHelpers.stringArgument(toolCall, "query") else { return nil }
        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.searchEmailFor,
            detail: .inline(query)
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id
        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments),
              let query = args["query"] as? String, !query.isEmpty
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'query' parameter"]),
                isError: true
            )
        }
        let maxResults = Int(args["max_results"] as? String ?? "") ?? Self.defaultResults
        let pageToken = args["page_token"] as? String

        do {
            let page = try await provider.searchEmails(
                query: query,
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
