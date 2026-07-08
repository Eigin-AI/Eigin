import Foundation

/// Static tool capabilities for the `email` domain, exposed to the
/// permissions UI even when no email integration is connected.
enum EmailToolCapabilities {
    static let all: [ToolCapability] = [
        ListEmailsTool.capability,
        SearchEmailsTool.capability,
        ReadEmailTool.capability,
        SendEmailTool.capability,
        ReplyEmailTool.capability,
    ]
}

/// Builds the five email tools for a connected ``EmailProvider`` backend.
enum EmailToolKit {
    static func tools(provider: any EmailProvider) -> [any Tool] {
        [
            ListEmailsTool(provider: provider),
            SearchEmailsTool(provider: provider),
            ReadEmailTool(provider: provider),
            SendEmailTool(provider: provider),
            ReplyEmailTool(provider: provider),
        ]
    }
}
