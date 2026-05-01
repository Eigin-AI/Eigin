import Foundation

enum ChatToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        ListChatsTool.capability,
        GetChatTranscriptTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        [
            ListChatsTool(spaceID: context.spaceID),
            GetChatTranscriptTool(spaceID: context.spaceID),
        ]
    }
}
