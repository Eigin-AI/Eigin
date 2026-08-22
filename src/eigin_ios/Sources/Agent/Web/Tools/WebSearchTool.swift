import Factory
import Foundation

struct WebSearchTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "web_search",
        displayName: Localized.Tools.Web.search,
        defaultPermissionLevel: .ask, category: .external
    )

    let name = "web_search"
    var isSmallContext: Bool = false

    /// Maximum content length in small-context mode (~375 tokens).
    /// Enough for a useful search digest without filling Gemma's 8k window.
    static let smallContextOutputLength = 1500
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
            description: "Search the web. Returns plain-text results.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "query": .init(
                        type: "string",
                        description: "The search query."
                    ),
                    "focus": .init(
                        type: "string",
                        description: "Optional: Restrict results to a curated set of trusted sites for a topic.",
                        enum: ["recipes", "books", "games", "music"]
                    ),
                ],
                required: ["query"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments),
              let query = (args["query"] as? String)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty
        else { return nil }
        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.searchWebFor,
            detail: .inline(query)
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
        guard let query = args["query"] as? String,
              !query.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or empty 'query' parameter"]),
                isError: true
            )
        }

        let focus = args["focus"] as? String
        let region = Locale.current.region?.identifier

        // Mojeek via the relay is the sole search path (background HTTP, no WebView).
        let json: String
        do {
            json = try await Container.shared.relayClient()
                .search(query: query, region: region, focus: focus)
        } catch {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [Self.failureMessage(for: error)]),
                isError: true
            )
        }

        guard !json.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [Self.genericFailureMessage]),
                isError: true
            )
        }

        var content = json
        var warnings: [String] = []

        let limit = isSmallContext ? Self.smallContextOutputLength : HTMLSanitizer
            .maxOutputLength
        if content.count > limit {
            content = String(content.prefix(limit))
            warnings.append("Content truncated to \(limit) characters.")
        }

        let result: [String: Any] = [
            "query": query,
            "content": content,
            "source": "Mojeek",
        ]
        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(
                result: result,
                warnings: warnings.isEmpty ? nil : warnings
            ),
            isError: false
        )
    }

    /// Agent-facing message for a search failure: gives the cause and a sensible next step,
    /// and steers the agent away from tight retry loops.
    static func failureMessage(for error: Error) -> String {
        guard let relayError = error as? RelayClientError else {
            return genericFailureMessage
        }
        switch relayError {
        case .rateLimit:
            return "Web search is temporarily at capacity (rate limited). Retrying in a few minutes may succeed; avoid immediate repeated retries."
        case .serviceUnavailable, .network, .upstream:
            return "Web search is temporarily unavailable — the search service could not be reached. It may recover shortly."
        default:
            return genericFailureMessage
        }
    }

    static let genericFailureMessage =
        "Web search is unavailable right now. Try again later; avoid retrying immediately."
}
