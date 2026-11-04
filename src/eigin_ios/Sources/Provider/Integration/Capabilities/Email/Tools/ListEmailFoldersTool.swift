import Foundation

/// Discovers folders and labels available in the connected account.
struct ListEmailFoldersTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "email_list_folders",
        displayName: Localized.Tools.Email.listFolders,
        description: Localized.Tools.Description.emailListFolders,
        defaultPermissionLevel: .ask, category: .email
    )

    let name = "email_list_folders"
    var isSmallContext = false
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
            description: "List available email folders or labels. Use returned IDs with email_list and email_search. Labels may overlap. Returns an error if folder access is unsupported.",
            parameters: JSONSchema(type: "object", properties: [:], required: [])
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        do {
            let folders = try await provider.listFolders()
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers
                    .output(result: ["folders": folders.map(\.jsonObject)]),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
