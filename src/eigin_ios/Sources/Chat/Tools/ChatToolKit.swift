import Foundation

enum ChatToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        ListChatsTool.capability,
        GetChatTranscriptTool.capability,
        SearchChatTranscriptTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        [
            ListChatsTool(spaceID: context.spaceID, accessPolicy: context.accessPolicy),
            GetChatTranscriptTool(
                spaceID: context.spaceID,
                currentChatID: context.chatID,
                accessPolicy: context.accessPolicy
            ),
            SearchChatTranscriptTool(
                spaceID: context.spaceID,
                currentChatID: context.chatID,
                accessPolicy: context.accessPolicy
            ),
        ]
    }
}
