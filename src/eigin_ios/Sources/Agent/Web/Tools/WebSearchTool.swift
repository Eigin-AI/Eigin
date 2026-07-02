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

        // Try the relay first (background HTTP, no WebView needed)
        if let json = try? await Container.shared.relayClient()
            .search(query: query, region: region, focus: focus),
            !json.isEmpty
        {
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

            let limit = isSmallContext ? Self.smallContextOutputLength : HTMLSanitizer
                .maxOutputLength
            if text.count > limit {
                text = String(text.prefix(limit))
                warnings.append("Content truncated to \(limit) characters.")
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
