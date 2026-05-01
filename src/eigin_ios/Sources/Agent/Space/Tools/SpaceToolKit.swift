import Foundation

enum SpaceToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        CreateSpaceTool.capability,
        EditSpaceTool.capability,
        ListSpacesTool.capability,
        MoveChatToSpaceTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        [
            CreateSpaceTool(),
            EditSpaceTool(),
            ListSpacesTool(),
            MoveChatToSpaceTool(chatID: context.chatID),
        ]
    }
}
