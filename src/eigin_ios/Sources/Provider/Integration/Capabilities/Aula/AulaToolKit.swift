import Foundation

/// Static tool capabilities for the `aula` domain, exposed to the permissions
/// UI even when no Aula integration is connected.
enum AulaToolCapabilities {
    static let all: [ToolCapability] = [
        GetAulaUpdatesTool.capability,
        ListAulaMessagesTool.capability,
        ReadAulaMessageTool.capability,
        GetAulaCalendarTool.capability,
        GetAulaChildrenTool.capability,
    ]
}

/// Builds the Aula tools for a connected ``AulaProvider`` backend.
enum AulaToolKit {
    static func tools(provider: any AulaProvider) -> [any Tool] {
        [
            GetAulaUpdatesTool(provider: provider),
            ListAulaMessagesTool(provider: provider),
            ReadAulaMessageTool(provider: provider),
            GetAulaCalendarTool(provider: provider),
            GetAulaChildrenTool(provider: provider),
        ]
    }
}
