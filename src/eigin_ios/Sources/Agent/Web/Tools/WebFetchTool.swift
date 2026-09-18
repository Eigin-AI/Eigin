import Foundation

struct WebFetchTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "web_fetch",
        displayName: Localized.Tools.Web.fetch,
        description: Localized.Tools.Description.webFetch,
        defaultPermissionLevel: .ask, category: .web
    )

    let name = "web_fetch"
    var isSmallContext: Bool = false

    /// Maximum content length in small-context mode (~500 tokens).
    /// Enough for a key paragraph or article intro without filling Gemma's 8k window.
    static let smallContextOutputLength = 2000
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .web
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
            description: "Fetch a URL and return its content as plain text.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "url": .init(
                        type: "string",
                        description: "The URL to fetch (http or https)."
                    ),
                ],
                required: ["url"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let url = ToolHelpers.stringArgument(toolCall, "url") else { return nil }
        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.fetchPageFrom,
            detail: .inline(url)
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
        guard let urlString = args["url"] as? String, !urlString.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or empty 'url' parameter"]),
                isError: true
            )
        }
        guard let url = URL(string: urlString) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid URL: \(urlString)"]),
                isError: true
            )
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Only http and https URLs are supported"]),
                isError: true
            )
        }

        // Check robots.txt to decide between background fetch and visible browsing
        let allowed = await RobotsTxtChecker.isAllowed(url: url)

        if allowed {
            // Site allows bots — fast background fetch, no UI
            do {
                var (text, warnings) = try await HTMLSanitizer.fetchAndSanitize(url: url)
                if isSmallContext, text.count > Self.smallContextOutputLength {
                    text = String(text.prefix(Self.smallContextOutputLength))
                    warnings
                        .append("Content truncated to \(Self.smallContextOutputLength) characters.")
                }
                let result: [String: Any] = ["url": urlString, "content": text]
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(
                        result: result,
                        warnings: warnings.isEmpty ? nil : warnings
                    ),
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

        // Site blocks bots — need visible browsing
        guard let onBrowse else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(errors: ["Cannot access this page — open the app to browse."]),
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
            if isSmallContext, text.count > Self.smallContextOutputLength {
                text = String(text.prefix(Self.smallContextOutputLength))
                warnings.append("Content truncated to \(Self.smallContextOutputLength) characters.")
            }
            let result: [String: Any] = ["url": urlString, "content": text]
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
