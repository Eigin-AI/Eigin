import Foundation

struct WebSearchTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "web_search",
        displayName: Localized.Tools.Web.search,
        defaultPermissionLevel: .ask, category: .external
    )

    let name = "web_search"
    var isSmallContext: Bool = false
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

    let onBrowse: BrowseHandler?

    init(onBrowse: BrowseHandler? = nil) {
        self.onBrowse = onBrowse
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
                ],
                required: ["query"]
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
        guard let query = args["query"] as? String,
              !query.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or empty 'query' parameter"]),
                isError: true
            )
        }

        // Try the relay first (background HTTP, no WebView needed)
        let relayResult = await RelaySearchClient.search(query: query)
        if case .success(let search) = relayResult {
            var content = search.json
            var warnings: [String] = []

            if content.count > HTMLSanitizer.maxOutputLength {
                content = String(content.prefix(HTMLSanitizer.maxOutputLength))
                warnings.append("Content truncated to \(HTMLSanitizer.maxOutputLength) characters.")
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

        // Relay failed — fall back to DuckDuckGo via browsing
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lite.duckduckgo.com/lite/?q=\(encoded)")
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Failed to build search URL"]),
                isError: true
            )
        }

        guard let onBrowse else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(
                        errors: ["Search requires an active chat session — open the app to search."]
                    ),
                isError: true
            )
        }

        let request = BrowsingRequest(
            id: id,
            url: url,
            toolDisplayName: Self.capability.displayName
        )
        let browsingResult = await onBrowse(request)

        switch browsingResult {
        case .success(var text):
            var warnings: [String] = []

            // Strip DuckDuckGo navigation preamble (region/time selectors)
            if let range = text.range(of: "(?m)^1\\.", options: .regularExpression) {
                text = String(text[range.lowerBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if text.count > HTMLSanitizer.maxOutputLength {
                text = String(text.prefix(HTMLSanitizer.maxOutputLength))
                warnings.append("Content truncated to \(HTMLSanitizer.maxOutputLength) characters.")
            }

            let result: [String: Any] = [
                "query": query,
                "content": text,
                "source": "DuckDuckGo",
                "source_url": url.absoluteString,
            ]
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(
                    result: result,
                    warnings: warnings.isEmpty ? nil : warnings
                ),
                isError: false
            )
        case .error(let message):
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [message]),
                isError: true
            )
        case .cancelled:
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Browsing was cancelled."]),
                isError: true
            )
        }
    }
}
